// Abstract transport interface. Three broadcast Stream<FcmMessage>
// (foreground / opened / initial), token APIs, lifecycle hooks. This file
// has NO firebase_messaging import — every consumer depends on this type,
// never on FcmTransportImpl directly.
//
// PROJECT SUBSTITUTIONS: none.

import 'fcm_message.dart';

enum FcmServiceStatus {
  uninitialized,
  ready,
  // Expected: simulator, no push entitlement, APNs gate timed out. NOT a crash.
  unavailable,
  // Unexpected: init threw. Surfaced via addError → AppBlocObserver → CrashReporter.
  failed,
}

enum FcmAuthorizationStatus {
  notDetermined,
  denied,
  authorized,
  provisional,
  ephemeral,
}

class FcmPermissionResult {
  final FcmAuthorizationStatus authorizationStatus;
  // True if Apple/Google still allow another prompt. When false + denied,
  // the controller treats as `deniedTerminal` and backs off the resume poll.
  final bool canPrompt;

  const FcmPermissionResult({
    required this.authorizationStatus,
    required this.canPrompt,
  });
}

// Lightweight telemetry envelope. The host project assigns a listener via
// FcmTransport.telemetry = (event) { analytics.track(event); }; nothing
// here knows about the host's SDK.
class FcmTelemetryEvent {
  final FcmTelemetryKind kind;
  final String? messageId;
  final int? dispatchLatencyMs;
  final String? variant; // payload type discriminator, when applicable
  final Object? error;

  const FcmTelemetryEvent({
    required this.kind,
    this.messageId,
    this.dispatchLatencyMs,
    this.variant,
    this.error,
  });
}

enum FcmTelemetryKind {
  delivered,
  opened,
  navigated,
  unknownVariant,
  malformedPayload,
  registerFailed,
  attestationFailed,
  initFailed,
}

abstract class FcmTransport {
  // --- streams -----------------------------------------------------------
  // All three are broadcast; a consumer that subscribes late receives only
  // subsequent events (intentional — initial-message arrives via
  // processInitialMessage()).
  Stream<FcmMessage> get onMessageStream;
  Stream<FcmMessage> get onOpenStream;
  Stream<FcmMessage> get onInitialMessageStream;

  // --- lifecycle ---------------------------------------------------------
  FcmServiceStatus get status;

  // Must be called once during app startup, BEFORE runApp().
  // Wraps Firebase.initializeApp() awareness, foreground-presentation
  // options, stream wiring. On any throw, status -> failed and the error
  // is routed via the cubit's addError → AppBlocObserver.
  Future<void> initialize();

  // Post-frame replay of getInitialMessage(). Call from a WidgetsBinding
  // addPostFrameCallback with an empirical delay (start at 300ms).
  // Fired-once; subsequent calls are no-ops.
  Future<void> processInitialMessage();

  // --- token APIs --------------------------------------------------------
  // On iOS, getApnsToken() is gated with bounded retry (~3s @ 300ms) inside
  // the impl. getToken() AWAITS that gate; never call getToken() from
  // outside without trusting it.
  Future<String?> getToken();
  Future<String?> getApnsToken();
  Future<void> deleteToken();

  // --- permissions -------------------------------------------------------
  Future<FcmPermissionResult> requestPermission({
    bool provisional = false,
  });
  Future<FcmPermissionResult> checkPermission();

  // --- iOS presentation --------------------------------------------------
  // Called once during init. Do NOT toggle at runtime (Rule 3a).
  Future<void> setForegroundPresentationOptions({
    bool alert = true,
    bool badge = true,
    bool sound = true,
  });

  // --- telemetry ---------------------------------------------------------
  // Host project assigns: transport.telemetry = (e) { analytics.track(e); };
  void Function(FcmTelemetryEvent)? telemetry;
}
