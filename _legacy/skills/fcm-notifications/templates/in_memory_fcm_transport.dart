// Test double. In bloc_tests / widget tests, register this in place of
// FcmTransportImpl so the cubit subscribes to controllable streams and
// no firebase_messaging code runs.
//
//   setUp(() {
//     getIt.registerSingleton<FcmTransport>(InMemoryFcmTransport());
//   });
//   tearDown(() => getIt.reset());
//
// Tests push messages with pushForeground / pushOpened / pushInitial and
// assert on the resulting cubit state. The skill prefers this over the
// kDebugMode-gated simulate() hook on the production impl — simulate()
// exists only for manual QA in dev builds.
//
// PROJECT SUBSTITUTIONS: none.

import 'dart:async';

import 'fcm_message.dart';
import 'fcm_transport.dart';

class InMemoryFcmTransport implements FcmTransport {
  final StreamController<FcmMessage> _onMessage =
      StreamController<FcmMessage>.broadcast();
  final StreamController<FcmMessage> _onOpen =
      StreamController<FcmMessage>.broadcast();
  final StreamController<FcmMessage> _onInitial =
      StreamController<FcmMessage>.broadcast();

  FcmServiceStatus _status = FcmServiceStatus.uninitialized;
  String? _fakeToken = 'in-memory-token';
  String? _fakeApnsToken = 'in-memory-apns-token';
  FcmPermissionResult _permission = const FcmPermissionResult(
    authorizationStatus: FcmAuthorizationStatus.authorized,
    canPrompt: false,
  );

  @override
  void Function(FcmTelemetryEvent)? telemetry;

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
    _status = FcmServiceStatus.ready;
  }

  @override
  Future<void> processInitialMessage() async {}

  @override
  Future<String?> getToken() async => _fakeToken;

  @override
  Future<String?> getApnsToken() async => _fakeApnsToken;

  @override
  Future<void> deleteToken() async {
    _fakeToken = null;
  }

  @override
  Future<FcmPermissionResult> requestPermission({bool provisional = false}) async {
    return _permission;
  }

  @override
  Future<FcmPermissionResult> checkPermission() async => _permission;

  @override
  Future<void> setForegroundPresentationOptions({
    bool alert = true,
    bool badge = true,
    bool sound = true,
  }) async {}

  // --- test surface ------------------------------------------------------

  void pushForeground(FcmMessage message) => _onMessage.add(message);
  void pushOpened(FcmMessage message) => _onOpen.add(message);
  void pushInitial(FcmMessage message) => _onInitial.add(message);

  void setFakeToken(String? token) {
    _fakeToken = token;
  }

  void setFakeApnsToken(String? token) {
    _fakeApnsToken = token;
  }

  void setPermission(FcmPermissionResult value) {
    _permission = value;
  }

  void setStatus(FcmServiceStatus value) {
    _status = value;
  }

  Future<void> dispose() async {
    await _onMessage.close();
    await _onOpen.close();
    await _onInitial.close();
  }
}
