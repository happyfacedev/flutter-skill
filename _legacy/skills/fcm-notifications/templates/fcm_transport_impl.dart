// Production FcmTransport. The ONLY file that imports firebase_messaging.
// Adapts RemoteMessage → FcmMessage before emitting on streams; every
// other consumer sees the Firebase-free DTO.
//
// PROJECT SUBSTITUTIONS:
//   <your_app>                  package name (the import below).
//   _kAndroidDefaultChannelId   keep `_v1` suffix; bump on importance change
//                               (Rule 8). MUST equal the
//                               `default_notification_channel_id` meta-data
//                               in AndroidManifest.xml — assert at init.
//   _kInitialMessagePostFrameDelayMs  300ms empirical default; tune per
//                               project if cold-start taps still miss on
//                               lower-end devices (Rule 6).

import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:injectable/injectable.dart';

import 'package:<your_app>/core/notifications/fcm_message.dart';
import 'package:<your_app>/core/notifications/fcm_transport.dart';

// MUST be top-level + @pragma + Firebase-init-first + registered pre-runApp.
// See Rule 1 in SKILL.md.
@pragma('vm:entry-point')
Future<void> fcmBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // Background isolate. NO BuildContext, NO UI render, NO Activity start
  // (Android API 31+). If the project wants to display a local notif from
  // here, the flutter_local_notifications instance must be re-initialized
  // inside this isolate — see reference §3 plugin-constraints table.
}

const String _kAndroidDefaultChannelId = 'notifications_v1';
const String _kAndroidDefaultChannelName = 'Notifications';
const String _kAndroidDefaultChannelDescription = 'Default notification channel.';
const int _kInitialMessagePostFrameDelayMs = 300;

const Duration _kApnsRetryTotal = Duration(seconds: 3);
const Duration _kApnsRetryStep = Duration(milliseconds: 300);

@Singleton(as: FcmTransport)
class FcmTransportImpl implements FcmTransport {
  final FirebaseMessaging _messaging;
  final FlutterLocalNotificationsPlugin _localNotifs;

  final StreamController<FcmMessage> _onMessage =
      StreamController<FcmMessage>.broadcast();
  final StreamController<FcmMessage> _onOpen =
      StreamController<FcmMessage>.broadcast();
  final StreamController<FcmMessage> _onInitial =
      StreamController<FcmMessage>.broadcast();

  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onOpenSub;
  bool _initialProcessed = false;

  FcmServiceStatus _status = FcmServiceStatus.uninitialized;

  @override
  void Function(FcmTelemetryEvent)? telemetry;

  FcmTransportImpl({
    FirebaseMessaging? messaging,
    FlutterLocalNotificationsPlugin? localNotifs,
  })  : _messaging = messaging ?? FirebaseMessaging.instance,
        _localNotifs = localNotifs ?? FlutterLocalNotificationsPlugin();

  @override
  Stream<FcmMessage> get onMessageStream => _onMessage.stream;

  @override
  Stream<FcmMessage> get onOpenStream => _onOpen.stream;

  @override
  Stream<FcmMessage> get onInitialMessageStream => _onInitial.stream;

  @override
  FcmServiceStatus get status => _status;

  @override
  Future<void> initialize() async {
    if (_status != FcmServiceStatus.uninitialized) return;
    try {
      // iOS Rule 2 — gate APNs before any token call. On simulators or
      // devices without push entitlement the token never arrives;
      // transition to `unavailable` (NOT `failed`) so the rest of the app
      // continues to work.
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final apns = await _awaitApnsToken();
        if (apns == null) {
          _status = FcmServiceStatus.unavailable;
          return;
        }
        // iOS Rule 3a — set once at init. Do NOT toggle at runtime.
        await setForegroundPresentationOptions();
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        await _ensureAndroidDefaultChannel();
      }

      _onMessageSub = FirebaseMessaging.onMessage.listen(_handleForeground);
      _onOpenSub = FirebaseMessaging.onMessageOpenedApp.listen(_handleOpened);

      _status = FcmServiceStatus.ready;
    } catch (e, st) {
      _status = FcmServiceStatus.failed;
      telemetry?.call(FcmTelemetryEvent(
        kind: FcmTelemetryKind.initFailed,
        error: e,
      ));
      // Surface to the cubit via the error path the host project owns. The
      // cubit's `addError(NotificationsInitFailure(e), st)` reaches
      // AppBlocObserver and the project's CrashReporter; this file MUST
      // NOT import Crashlytics directly (core-architecture.md).
      Zone.current.handleUncaughtError(e, st);
    }
  }

  @override
  Future<void> processInitialMessage() async {
    if (_initialProcessed) return;
    _initialProcessed = true;
    final completer = Completer<void>();
    SchedulerBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(
        const Duration(milliseconds: _kInitialMessagePostFrameDelayMs),
      );
      final msg = await _messaging.getInitialMessage();
      if (msg != null) {
        _onInitial.add(_adapt(msg));
      }
      completer.complete();
    });
    return completer.future;
  }

  @override
  Future<String?> getToken() async {
    if (_status == FcmServiceStatus.unavailable) return null;
    return _messaging.getToken();
  }

  @override
  Future<String?> getApnsToken() => _messaging.getAPNSToken();

  @override
  Future<void> deleteToken() => _messaging.deleteToken();

  @override
  Future<FcmPermissionResult> requestPermission({bool provisional = false}) async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: provisional,
    );
    return _mapPermission(settings);
  }

  @override
  Future<FcmPermissionResult> checkPermission() async {
    final settings = await _messaging.getNotificationSettings();
    return _mapPermission(settings);
  }

  @override
  Future<void> setForegroundPresentationOptions({
    bool alert = true,
    bool badge = true,
    bool sound = true,
  }) async {
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: alert,
      badge: badge,
      sound: sound,
    );
  }

  // --- internals ---------------------------------------------------------

  // QA hook gated by kDebugMode. Use sparingly — production tests should
  // depend on InMemoryFcmTransport instead (host registers it in setUp).
  @visibleForTesting
  void simulate({
    required FcmMessage message,
    required _FcmTapPhase phase,
  }) {
    assert(kDebugMode, 'simulate() must only be called in debug builds.');
    switch (phase) {
      case _FcmTapPhase.foreground:
        _onMessage.add(message);
      case _FcmTapPhase.opened:
        _onOpen.add(message);
      case _FcmTapPhase.initial:
        _onInitial.add(message);
    }
  }

  Future<String?> _awaitApnsToken() async {
    final start = DateTime.now();
    while (DateTime.now().difference(start) < _kApnsRetryTotal) {
      final token = await _messaging.getAPNSToken();
      if (token != null) return token;
      await Future<void>.delayed(_kApnsRetryStep);
    }
    return null;
  }

  Future<void> _ensureAndroidDefaultChannel() async {
    // Rule 8 — never reuse a channel id across an importance change.
    final android = _localNotifs.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _kAndroidDefaultChannelId,
        _kAndroidDefaultChannelName,
        description: _kAndroidDefaultChannelDescription,
        importance: Importance.high,
      ),
    );
  }

  void _handleForeground(RemoteMessage msg) {
    telemetry?.call(FcmTelemetryEvent(
      kind: FcmTelemetryKind.delivered,
      messageId: msg.messageId,
    ));
    _onMessage.add(_adapt(msg));
    // Android foreground display — Rule 3b path (A). If the project picks
    // path (B), remove this call. NEVER wire both.
    if (defaultTargetPlatform == TargetPlatform.android &&
        msg.notification != null) {
      _showAndroidLocalNotif(msg);
    }
  }

  void _handleOpened(RemoteMessage msg) {
    telemetry?.call(FcmTelemetryEvent(
      kind: FcmTelemetryKind.opened,
      messageId: msg.messageId,
    ));
    _onOpen.add(_adapt(msg));
  }

  Future<void> _showAndroidLocalNotif(RemoteMessage msg) async {
    // Rule 3b — thread messageId into the local-notif payload so
    // onDidReceiveNotificationResponse can dedup against onMessageOpenedApp
    // on the 500ms window. Without this, dedup is silently broken.
    final payload = jsonEncode({
      'messageId': msg.messageId,
      'data': msg.data,
    });
    await _localNotifs.show(
      msg.hashCode,
      msg.notification?.title,
      msg.notification?.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          msg.notification?.android?.channelId ?? _kAndroidDefaultChannelId,
          _kAndroidDefaultChannelName,
          channelDescription: _kAndroidDefaultChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: payload,
    );
  }

  FcmMessage _adapt(RemoteMessage msg) {
    return FcmMessage(
      messageId: msg.messageId,
      data: Map<String, dynamic>.from(msg.data),
      notification: msg.notification == null
          ? null
          : FcmNotificationBlock(
              title: msg.notification!.title,
              body: msg.notification!.body,
              androidChannelId: msg.notification?.android?.channelId,
            ),
      sentTime: msg.sentTime,
    );
  }

  FcmPermissionResult _mapPermission(NotificationSettings s) {
    final auth = switch (s.authorizationStatus) {
      AuthorizationStatus.authorized => FcmAuthorizationStatus.authorized,
      AuthorizationStatus.denied => FcmAuthorizationStatus.denied,
      AuthorizationStatus.notDetermined => FcmAuthorizationStatus.notDetermined,
      AuthorizationStatus.provisional => FcmAuthorizationStatus.provisional,
    };
    // `canPrompt` heuristic: iOS notDetermined or Android-API-pre-13 can
    // always re-prompt; iOS denied is terminal (Settings only). Refine per
    // platform if your project needs finer granularity.
    final canPrompt = auth == FcmAuthorizationStatus.notDetermined ||
        auth == FcmAuthorizationStatus.provisional;
    return FcmPermissionResult(authorizationStatus: auth, canPrompt: canPrompt);
  }

  @disposeMethod
  Future<void> dispose() async {
    await _onMessageSub?.cancel();
    await _onOpenSub?.cancel();
    await _onMessage.close();
    await _onOpen.close();
    await _onInitial.close();
  }
}

enum _FcmTapPhase { foreground, opened, initial }
