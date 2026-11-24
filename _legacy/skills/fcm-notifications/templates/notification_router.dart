// Pure mapper from payload → NavigationIntent → router.go(). Two entry
// points: foreground dispatch renders UI, background dispatch only emits
// telemetry and buffers the intent (no BuildContext in the bg isolate).
//
// CRITICAL — NavigationIntent overrides == / hashCode. PendingIntentStore
// uses ValueNotifier<NavigationIntent?>, which dedups via !=. Default
// reference equality means two intents-to-the-same-screen are seen as
// distinct and the store fires twice (or never, depending on order).
//
// Rule 7 — router is NOT a permission gate. Destination pages handle
// "not found / forbidden" gracefully. Router only resolves to "where
// should we go", never to "is the user allowed."
//
// Adapt §1.4 for foreign nav stacks: replace context.go() with the
// stack-replacing primitive (AutoRoute router.replaceAll, Beamer
// beamToReplacement, Navigator pushNamedAndRemoveUntil). Stack-additive
// push() is wrong here — breaks browser back, deep-link callbacks, and
// the snapshot the auth/startup pipeline expects.
//
// PROJECT SUBSTITUTIONS:
//   <your_app>                package name (imports below).
//   GoRouter / context.go     swap for your router per the §1.4 matrix.
//   ARB keys                  localize per your i18n setup.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:injectable/injectable.dart';

import 'package:<your_app>/core/notifications/notification_payload.dart';
import 'package:<your_app>/core/notifications/pending_intent_store.dart';
import 'package:<your_app>/core/notifications/fcm_transport.dart';

@immutable
class NavigationIntent {
  final String location;
  final Object? extra;

  const NavigationIntent({required this.location, this.extra});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NavigationIntent &&
          other.location == location &&
          other.extra == extra;

  @override
  int get hashCode => Object.hash(location, extra);
}

@singleton
class NotificationRouter {
  final GlobalKey<NavigatorState> _navKey;
  final PendingIntentStore _pending;
  final void Function(FcmTelemetryEvent)? _telemetry;

  NotificationRouter(this._navKey, this._pending, {void Function(FcmTelemetryEvent)? telemetry})
      : _telemetry = telemetry;

  // Called from the cubit's foreground / opened / initial stream handlers.
  void dispatchInForeground(NotificationPayload payload) {
    final intent = _resolve(payload);
    if (intent == null) {
      _emit(FcmTelemetryKind.unknownVariant, payload);
      _showUnknownVariantSnackbar();
      return;
    }
    final ctx = _navKey.currentContext;
    if (ctx == null) {
      // Router not ready — buffer for the next foreground tick.
      _pending.set(intent);
      return;
    }
    _popAllModals(ctx);
    ctx.go(intent.location, extra: intent.extra);
    _emit(FcmTelemetryKind.navigated, payload);
  }

  // Background isolate — NO UI render, NO context. Telemetry + buffer only.
  // The intent is replayed on next foreground dispatch through PendingIntentStore.
  void dispatchInBackground(NotificationPayload payload) {
    final intent = _resolve(payload);
    if (intent == null) {
      _emit(FcmTelemetryKind.unknownVariant, payload);
      return;
    }
    _pending.set(intent);
  }

  // Owned: payload → intent mapping. Replace cases with project payloads.
  NavigationIntent? _resolve(NotificationPayload payload) {
    return switch (payload) {
      OrderShippedPayload(:final orderId) =>
        NavigationIntent(location: '/orders/$orderId'),
      ChatMessagePayload(:final threadId) =>
        NavigationIntent(location: '/chat/$threadId'),
      UnknownPayload() => null,
      MalformedPayload() => null,
    };
  }

  void _popAllModals(BuildContext ctx) {
    final nav = Navigator.of(ctx, rootNavigator: true);
    nav.popUntil((r) => r.isFirst);
  }

  void _showUnknownVariantSnackbar() {
    final ctx = _navKey.currentContext;
    if (ctx == null) return;
    ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(
      const SnackBar(
        // localize per your i18n setup
        content: Text("This update isn't available in your version yet."),
      ),
    );
  }

  void _emit(FcmTelemetryKind kind, NotificationPayload payload) {
    _telemetry?.call(FcmTelemetryEvent(
      kind: kind,
      variant: payload.variant,
    ));
  }
}
