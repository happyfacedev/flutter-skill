// @singleton HydratedCubit owning FCM token lifecycle + permission state.
// State (TokenRegistrationState + PermissionState) lives in
// notifications_state.dart — keep that file in sync.
//
// Private cubit fields (Completer, dedup map, currentUserId) are NOT in
// state and NOT in toJson. They are transient runtime state — persisting
// them across restarts would wedge the gate.
//
// onUserChanged is called from bootstrapper.dart via a BlocListener on
// AuthCubit. This file MUST NOT take AuthCubit as a dependency
// (cubit-creation Rule 5).
//
// PROJECT SUBSTITUTIONS:
//   <your_app>                package name (imports below).
//   DeviceTokensRepository    your repo for register/delete RPCs;
//                             shape lives in network-creation-supabase.
//   NotificationsInitFailure  failure variant emitted when initialize()
//                             throws (shape lives in failure-modeling).

import 'dart:async';
import 'dart:math';

import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:injectable/injectable.dart';

import 'package:<your_app>/core/notifications/device_id_provider.dart';
import 'package:<your_app>/core/notifications/device_tokens_repository.dart';
import 'package:<your_app>/core/notifications/fcm_message.dart';
import 'package:<your_app>/core/notifications/fcm_transport.dart';
import 'package:<your_app>/core/notifications/notification_payload.dart';
import 'package:<your_app>/core/notifications/notification_router.dart';
import 'package:<your_app>/core/notifications/notifications_state.dart';

const Duration _kRegisterTimeout = Duration(seconds: 20);
const Duration _kHeartbeatInterval = Duration(days: 7);
const Duration _kTapDedupWindow = Duration(milliseconds: 500);

class _RegisterInFlight {
  final Completer<void> completer;
  final String token;
  final String userId;
  final String deviceId;
  _RegisterInFlight({
    required this.completer,
    required this.token,
    required this.userId,
    required this.deviceId,
  });
}

@singleton
class NotificationsCubit extends HydratedCubit<NotificationsState> {
  final FcmTransport _transport;
  final DeviceTokensRepository _repository;
  final DeviceIdProvider _deviceIds;
  final NotificationRouter _router;

  StreamSubscription<FcmMessage>? _onMessageSub;
  StreamSubscription<FcmMessage>? _onOpenSub;
  StreamSubscription<FcmMessage>? _onInitialSub;

  _RegisterInFlight? _inFlight;
  final Map<String, DateTime> _recentTaps = {};
  String? _currentUserId;

  NotificationsCubit(
    this._transport,
    this._repository,
    this._deviceIds,
    this._router,
  ) : super(const NotificationsState()) {
    _onMessageSub = _transport.onMessageStream.listen(_handleForeground);
    _onOpenSub = _transport.onOpenStream.listen(_handleOpened);
    _onInitialSub = _transport.onInitialMessageStream.listen(_handleOpened);
  }

  // --- Token lifecycle (Rule 4 + Rule 5) --------------------------------

  // Gate: register only when live ≠ persisted OR > 7d since last register.
  // Heartbeat fires regardless of permission state so the backend's
  // last_seen_at refreshes for denied-permission users.
  Future<void> refreshToken({String? userId}) async {
    final uid = userId ?? _currentUserId;
    if (uid == null) return;
    _currentUserId = uid;

    final live = await _transport.getToken();
    if (live == null) return;

    final persisted = state.token.persistedToken;
    final lastAt = state.token.lastRegisteredAt;
    final stale = lastAt == null ||
        DateTime.now().difference(lastAt) > _kHeartbeatInterval;
    if (live == persisted && !stale) return;

    await _registerCoalesced(token: live, userId: uid);
  }

  // Called from bootstrapper.dart via BlocListener<AuthCubit, AuthState>.
  // Handles login, logout (newUserId == null), AND account switch (A → B).
  Future<void> onUserChanged(String? newUserId) async {
    final previous = _currentUserId;
    _currentUserId = newUserId;
    if (newUserId == null) {
      await _dissociateOnLogout(previousUserId: previous);
      return;
    }
    await refreshToken(userId: newUserId);
  }

  Future<void> _registerCoalesced({
    required String token,
    required String userId,
  }) async {
    final existing = _inFlight;
    if (existing != null &&
        existing.token == token &&
        existing.userId == userId) {
      try {
        await existing.completer.future;
      } catch (_) {/* surfaced via state */}
      return;
    }
    // A stale in-flight (different user or token) is NOT cancelled; its
    // resolution will be dropped by the triple-axis check below.
    final deviceId = await _deviceIds.get();
    final completer = Completer<void>();
    final snapshot = _RegisterInFlight(
      completer: completer,
      token: token,
      userId: userId,
      deviceId: deviceId,
    );
    _inFlight = snapshot;
    emit(state.copyWith(
      token: state.token.copyWith(status: TokenRegistrationStatus.registering),
    ));

    try {
      await _repository
          .registerDeviceToken(
            deviceId: deviceId,
            token: token,
            userId: userId,
          )
          .timeout(_kRegisterTimeout);
      _onRegisterResolved(snapshot, success: true);
      completer.complete();
    } catch (e, st) {
      _onRegisterResolved(snapshot, success: false, error: e);
      completer.completeError(e, st);
      addError(e, st);
    }
  }

  // Triple-axis drop: currentUserId == null, user_id mismatch, or fresher
  // token having arrived. Drops the result rather than writing it to state.
  void _onRegisterResolved(
    _RegisterInFlight snapshot, {
    required bool success,
    Object? error,
  }) {
    if (_inFlight == snapshot) _inFlight = null;
    final current = _currentUserId;
    if (current == null) return; // auth not hydrated; do NOT default-pass
    if (snapshot.userId != current) return; // user switched mid-flight

    if (success) {
      emit(state.copyWith(
        token: state.token.copyWith(
          status: TokenRegistrationStatus.registered,
          persistedToken: snapshot.token,
          lastRegisteredAt: DateTime.now(),
        ),
      ));
    } else {
      emit(state.copyWith(
        token: state.token.copyWith(
          status: TokenRegistrationStatus.failed,
          lastError: error,
        ),
      ));
    }
  }

  // Rule 5 — getToken() FIRST; dissociate by (device_id, live_token).
  // If the RPC fails, persisted state STILL clears. Logout never blocks.
  Future<void> _dissociateOnLogout({String? previousUserId}) async {
    final liveToken = await _transport.getToken();
    final dissociateToken = liveToken ?? state.token.persistedToken;
    final deviceId = await _deviceIds.get();
    try {
      if (dissociateToken != null && previousUserId != null) {
        await _repository.deleteDeviceToken(
          deviceId: deviceId,
          token: dissociateToken,
          userId: previousUserId,
        );
      }
      await _transport.deleteToken();
    } catch (e, st) {
      addError(e, st);
    } finally {
      emit(state.copyWith(token: const TokenRegistrationState()));
    }
  }

  // --- Permission flow (Rule 7) -----------------------------------------

  // Returns the resolved status AND mutates state. Backs off when terminal.
  Future<NotificationPermissionStatus> refreshFromPermissionState() async {
    if (state.permission.status == NotificationPermissionStatus.deniedTerminal) {
      return state.permission.status;
    }
    final result = await _transport.checkPermission();
    final resolved = _mapPermission(result);
    if (resolved != state.permission.status) {
      emit(state.copyWith(permission: PermissionState(status: resolved)));
    }
    return resolved;
  }

  Future<NotificationPermissionStatus> requestPermission() async {
    final result = await _transport.requestPermission();
    final resolved = _mapPermission(result);
    emit(state.copyWith(permission: PermissionState(status: resolved)));
    if (resolved == NotificationPermissionStatus.authorized ||
        resolved == NotificationPermissionStatus.provisional) {
      await refreshToken();
    }
    return resolved;
  }

  NotificationPermissionStatus _mapPermission(FcmPermissionResult r) {
    return switch (r.authorizationStatus) {
      FcmAuthorizationStatus.authorized => NotificationPermissionStatus.authorized,
      FcmAuthorizationStatus.provisional => NotificationPermissionStatus.provisional,
      FcmAuthorizationStatus.ephemeral => NotificationPermissionStatus.ephemeral,
      FcmAuthorizationStatus.notDetermined => NotificationPermissionStatus.notDetermined,
      FcmAuthorizationStatus.denied => r.canPrompt
          ? NotificationPermissionStatus.denied
          : NotificationPermissionStatus.deniedTerminal,
    };
  }

  // --- Tap dispatch (Rule 3b + Rule 6) ----------------------------------

  void _handleForeground(FcmMessage msg) {
    final payload = NotificationPayload.fromMessage(msg);
    _router.dispatchInForeground(payload);
  }

  void _handleOpened(FcmMessage msg) {
    if (_isDuplicateTap(msg.messageId)) return;
    final payload = NotificationPayload.fromMessage(msg);
    _router.dispatchInForeground(payload);
  }

  bool _isDuplicateTap(String? messageId) {
    if (messageId == null) return false;
    final now = DateTime.now();
    _recentTaps.removeWhere((_, when) => now.difference(when) > _kTapDedupWindow);
    final last = _recentTaps[messageId];
    if (last != null && now.difference(last) <= _kTapDedupWindow) return true;
    _recentTaps[messageId] = now;
    return false;
  }

  // Full-jitter helper for pending-registration retry on resume.
  Duration nextRetryJitter() => Duration(milliseconds: Random().nextInt(60 * 1000));

  // --- HydratedCubit ----------------------------------------------------

  @override
  NotificationsState? fromJson(Map<String, dynamic> json) =>
      NotificationsState.fromJson(json);

  @override
  Map<String, dynamic>? toJson(NotificationsState state) => state.toJson();

  @override
  Future<void> close() async {
    await _onMessageSub?.cancel();
    await _onOpenSub?.cancel();
    await _onInitialSub?.cancel();
    return super.close();
  }
}
