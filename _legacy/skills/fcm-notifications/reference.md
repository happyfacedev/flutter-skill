# FCM Notifications — Reference

The SKILL.md body covers what to do; this file covers why, the edge cases, and the platform / backend contracts that the app's correctness depends on.

## §0 Architecture diagram

```
                ┌──────────────────────────────────────┐
                │     FcmMessage  (Firebase-free DTO)  │
                │  { messageId, data, notification? }  │
                │  Built by FcmTransportImpl from      │
                │  RemoteMessage; emitted on all       │
                │  streams. Keeps every consumer free  │
                │  of firebase_messaging imports.      │
                └──────────────────────────────────────┘
                             ▲
                ┌────────────┴─────────────────────────┐
                │      FcmTransport (abstract)         │
                │  Contract: streams + token APIs      │
                │                                      │
                │   ▼ implemented by                   │
                │                                      │
                │  ┌───────────────────────────────┐   │
                │  │ FcmTransportImpl              │   │
                │  │ (production @Singleton)       │   │
                │  │ - adapts RemoteMessage → DTO  │   │
                │  │ - initialize() (pre-runApp)   │   │
                │  │ - getToken / getApnsToken     │   │
                │  │ - deleteToken                 │   │
                │  │ - simulate() (kDebugMode QA)  │   │
                │  │ - background handler          │   │
                │  │   (top-level @pragma)         │   │
                │  │ + telemetry observer hook     │   │
                │  └───────────────────────────────┘   │
                │  ┌───────────────────────────────┐   │
                │  │ InMemoryFcmTransport (tests)  │   │
                │  │ pushes FcmMessage instances   │   │
                │  │ — no firebase_messaging dep   │   │
                │  └───────────────────────────────┘   │
                └────────────┬─────────────────────────┘
                             │ Stream<FcmMessage>
                ┌────────────▼─────────────────────────┐
                │     NotificationsCubit               │
                │  (HydratedCubit + @singleton)        │
                │                                      │
                │  State: TokenRegistrationState +     │
                │         PermissionState              │
                │  Private fields (NOT persisted):     │
                │    _registerInFlight: Completer      │
                │    _recentTaps: Map<msgId, DateTime> │
                │    _currentUserId: String?           │
                │                                      │
                │  Token lifecycle (coalesced):        │
                │    register / refresh / delete       │
                │    onUserChanged() — called from     │
                │      bootstrapper.dart BlocListener  │
                │  Tap dispatch: payload → router      │
                │  Resume-poll: refreshFromPermission… │
                │  Errors: addError(failure, st)       │
                │    → AppBlocObserver → CrashReporter │
                └────────────┬─────────────────────────┘
                             │ payload
                ┌────────────▼─────────────────────────┐
                │       NotificationRouter             │
                │  (pure mapper, no state)             │
                │  dispatchInForeground(payload)       │
                │  dispatchInBackground(payload) →     │
                │    telemetry + buffer; no UI render  │
                └────────────┬─────────────────────────┘
                             │ intent
                ┌────────────▼─────────────────────────┐
                │     PendingIntentStore                │
                │  ValueNotifier<NavigationIntent?>     │
                │  Requires == / hashCode on intent     │
                │  (else dedup semantics break)         │
                └───────────────────────────────────────┘
                             │
                      (project's router)
```

---

## §1 Platform setup & greenfield checklist

### Versions and platform floors

| Concern | Floor | Why |
|---|---|---|
| `firebase_messaging` | ≥ 16.1.1 | iOS 18 duplicate-notification regression re-fixed in 16.1.1 |
| `flutter_local_notifications` | ≥ 21.0.0 | v21 is current stable; v22 prerelease (Android 16) |
| Flutter SDK | ≥ 3.38.0 | iOS 26 + Xcode 26 support |
| iOS deployment target | ≥ 13.0 | required by `firebase_messaging` 15+ |
| Android `compileSdk` | 35 | current FCM target |
| Xcode | ≥ 26.0 | iOS 26 SDK |

### Portability matrix (foreign Flutter projects)

The skill targets bloc/cubit + injectable + GoRouter + dartz + freezed + flutter_local_notifications. Foreign-project swaps:

| Concern | Hard requirement | Skill assumes | Adapt for foreign |
|---|---|---|---|
| State management | controller with coalesced register/refresh/delete | bloc/cubit | Riverpod `Notifier`, MobX, `ChangeNotifier` |
| Persisted token | reconciled against `getToken()` on logout | `HydratedCubit` | `shared_preferences`, SQLite, secure storage |
| DI | app-wide singleton for `FcmService` | `injectable` + `get_it` | Riverpod `keepAlive`, manual `get_it.registerSingleton` |
| Router | stack-replacing primitive | GoRouter `context.go()` | AutoRoute `replaceAll`, Beamer `beamToReplacement`, `pushNamedAndRemoveUntil` |
| Repository | typed-failure wrapper | `Either<Failure, T>` (dartz) | `Result<T,E>`, `fpdart`, thrown typed exceptions |
| Payload modelling | discriminated union over data map | Dart 3 native `sealed class` | Freezed if project already uses it |
| Dev hook gate | — | `kDebugMode` | — (do NOT use project-only `EnvConfig.isDev` in templates) |

N-swap count for a foreign Flutter project: typically 3–4 mechanical substitutions across templates.

### Firebase project setup

1. Firebase Console → **Add project**.
2. **Add Android app** → package name → download `google-services.json` → place in `android/app/`.
3. **Add iOS app** → bundle id → download `GoogleService-Info.plist` → drag into `ios/Runner/` in Xcode (NOT just the filesystem — Xcode must register it).
4. **Cloud Messaging** → Apple → upload `.p8` APNs key with Key ID + Team ID (see [iOS setup checklist](templates/ios_setup_checklist.md)).

### Android setup

1. `android/build.gradle.kts`: add `classpath("com.google.gms:google-services:4.4.x")` to buildscript dependencies.
2. `android/app/build.gradle.kts`: `apply(plugin = "com.google.gms.google-services")`.
3. `minSdk` ≥ 21.
4. Add `[android_manifest_snippet.xml](templates/android_manifest_snippet.xml)` contents to `android/app/src/main/AndroidManifest.xml`.
5. Provide `@drawable/ic_notification` (white-silhouette PNG; without it, system-rendered notifications show a grey square in production).
6. ProGuard / R8 — if using Freezed payloads, keep generated fromJson:
   ```
   -keep class **.*Payload { *; }
   -keepclassmembers class * { @com.google.firebase.* *; }
   ```

### iOS setup

See [ios_setup_checklist.md](templates/ios_setup_checklist.md) for the full checklist (capabilities, entitlements, APNs key, SPM vs CocoaPods, AppDelegate vs SceneDelegate, sandbox matrix).

### Greenfield verification

After setup:

1. `flutter run` on a physical iOS device (NOT simulator — APNs unavailable).
2. After login, verify `TokenRegistrationStatus` reaches `registered`.
3. Send a test push via FCM HTTP v1 (Console "Test send" uses a different shape — see §11).

---

## §2 FcmTransport anatomy

`FcmTransport` is an abstract interface. Production: `FcmTransportImpl` (`@Singleton(as: FcmTransport)`). Tests: `InMemoryFcmTransport` (registered in `setUp`).

### Streams

Three broadcast `Stream<FcmMessage>`:
- `onMessageStream` — fired by FCM `onMessage` (foreground arrival).
- `onOpenStream` — fired by FCM `onMessageOpenedApp` (warm-tap from background).
- `onInitialMessageStream` — fired exactly once during `processInitialMessage()` if `getInitialMessage()` returns non-null.

Broadcast (not single-subscription): the cubit subscribes; in some projects a debug overlay also subscribes. Late subscribers receive only subsequent events — `processInitialMessage()` only fires once, regardless of who's listening.

### Init lifecycle

`initialize()` runs **before `runApp()`**:
1. iOS: gate APNs (Rule 2). On timeout → `status = unavailable`; return early.
2. iOS: `setForegroundPresentationOptions(...)` once (Rule 3a).
3. Android: ensure default channel exists at the declared importance (Rule 8).
4. Wire `onMessage` + `onMessageOpenedApp` subscriptions.
5. On any throw → `status = failed`, emit `FcmTelemetryKind.initFailed`, propagate via `Zone.current.handleUncaughtError`. The cubit's `AppBlocObserver` integration ultimately routes to the project's `CrashReporter`. The transport itself MUST NOT import Crashlytics.

### `simulate()` dev hook

`@visibleForTesting` method on `FcmTransportImpl`, asserted to `kDebugMode`. It's a *manual* QA hook for in-app dev panels — production tests inject `InMemoryFcmTransport` instead.

### Telemetry observer

`FcmTransport.telemetry` is a settable `void Function(FcmTelemetryEvent)?`. The host project wires it in the composition root:

```dart
transport.telemetry = (event) {
  analytics.track('fcm_${event.kind.name}', properties: {
    'messageId': event.messageId,
    'variant': event.variant,
    'dispatchLatencyMs': event.dispatchLatencyMs,
  });
};
```

Events: `delivered`, `opened`, `navigated`, `unknownVariant`, `malformedPayload`, `registerFailed`, `attestationFailed`, `initFailed`.

---

## §3 Background + foreground display

### Background isolate plugin constraints

`onBackgroundMessage` runs in a fresh isolate. Many plugins are unavailable or need explicit re-init:

| Plugin | Status in bg isolate |
|---|---|
| `firebase_core` / `firebase_messaging` | Available; `Firebase.initializeApp()` MUST be the first call. |
| `flutter_local_notifications` | Available, but needs `initialize()` in the bg isolate before `.show()`. |
| `shared_preferences` | Available. Reads see foreground writes (eventually). |
| `hive` | Needs box re-open in the isolate. |
| `supabase_flutter` client | NOT initialised. RPCs from the bg handler require a fresh client instance. |
| Anything depending on `BuildContext` | Unavailable — no widget tree. |
| Android Activity start | Forbidden by API 31+ background-start restrictions. Display a local notif; routing happens on user-tap. |

The handler MUST be top-level / `static`, `@pragma('vm:entry-point')`, with `Firebase.initializeApp()` first, registered pre-`runApp`. See Rule 1.

### Foreground display

**iOS:** `setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true)` once at init (Rule 3a). Toggling `alert: false` at runtime is broken (FlutterFire #17124, #10804) — it can suppress `onMessage` delivery in addition to display.

**Android:** No automatic foreground tray render. Wire `flutter_local_notifications`. Pick exactly ONE tap path (Rule 3b):
- **(A)** `onMessage` re-displays via local notif → tap fires `onDidReceiveNotificationResponse` → handler decodes the JSON `payload` string for `messageId` and dedups against `onMessageOpenedApp`'s 500ms window.
- **(B)** `onMessage` displays only; tap arrives via `onMessageOpenedApp`. Requires the sender to include a `notification` block.

Path A is more flexible (per-message customization, payload size > 4 KB-from-data alone). Path B is simpler but loses data-only message taps.

### Data-only vs notification messages

| Sender block | Foreground `onMessage` | Background isolate | Tap | System-tray render |
|---|---|---|---|---|
| `data` only | ✓ fires | ✓ fires (bg isolate) | iOS: no tap event (no tray render); Android: depends on path A/B | None unless client renders via `flutter_local_notifications` |
| `notification` only | ✓ fires | App-state-dependent | `onMessageOpenedApp` fires on tap | System renders automatically (iOS always; Android only when bg/terminated) |
| `notification` + `data` | ✓ fires | App-state-dependent | `onMessageOpenedApp` carries `data` | System renders the notification block |

For `content-available: 1` silent push on iOS:
- Wakes the bg isolate.
- Throttled by iOS to ≈2–3/hour effective per device (varies by Low Power Mode, Focus, DnD).
- **Not a sync mechanism** — design for unreliable delivery.

`priority: high` on Android: required for timely delivery on Doze-mode devices; without it, FCM may batch and delay.

### Tap dedup (Rule 3b path A specifically)

```dart
// In onDidReceiveNotificationResponse:
final decoded = jsonDecode(response.payload!);
final messageId = decoded['messageId'] as String?;
// Forward to NotificationsCubit's tap handler, which applies the
// 500ms window keyed on messageId (see _isDuplicateTap in the cubit).
```

Without the threaded `messageId`, the dedup key is missing and double-fires reach the router.

---

## §4 Token lifecycle

The cubit's `refreshToken({String? userId})` is the single public entry. Internally, every register path runs through `_registerCoalesced` (Rule 4).

### Register gate

Skip the register RPC when **live token == persisted token AND last register < 7 days ago**. This cuts ~50k DAU × ~1 register/day → registration-on-change only.

The 7-day heartbeat fires **regardless of permission state**. Reason: backend §8.3 reaps tokens with stale `last_seen_at`. A user who denies permission still needs `last_seen_at` to refresh — otherwise their row is reaped and the moment they grant permission, the server has no row to deliver to.

### Coalesce gate

Single `_RegisterInFlight` per cubit holds `(Completer, token, userId, deviceId)`. Concurrent triggers (auth-change, `onTokenRefresh`, permission-grant) for the same `(token, userId)` await the in-flight future. A different `(token, userId)` starts a new in-flight; the stale one is NOT cancelled — its resolution is dropped at completion time.

### Bounded timeout + `completeError`

The RPC runs under `_kRegisterTimeout` (20s default). On timeout or failure:
- `completer.completeError(failure)` so awaiting callers raise via their `await`.
- `addError(e, st)` so `AppBlocObserver` surfaces to the global snackbar + `CrashReporter`.
- State transitions to `failed` with the error preserved on `lastError`.

The gate ALWAYS clears (`_inFlight = null`), regardless of outcome — never on success alone.

### Triple-axis stale drop

When the in-flight future resolves, the cubit drops the result if ANY:
1. `_currentUserId == null` — auth not yet hydrated. Null must NOT default-pass.
2. `snapshot.userId != _currentUserId` — user switched mid-flight.
3. `snapshot.token != currentLiveToken` — a fresher `onTokenRefresh` arrived; the new caller will start its own register.

This closes the "I think I registered, but actually the new user is unregistered" footgun.

### Logout (Rule 5)

`_dissociateOnLogout(previousUserId)`:
1. `getToken()` FIRST to fetch the live token. Don't trust persisted alone — cloud restore may have hydrated a stale token from another device.
2. Dissociate by `(device_id, live_token, previousUserId)`.
3. `deleteToken()` (FCM-side).
4. Clear persisted state in `finally` — logout UX never blocks on the RPC. Orphans are reaped by §8.3 TTL.

### Account switching

`onUserChanged(newUserId)`:
- `null` → logout flow.
- Non-null → reconcile via `refreshToken(userId: newUserId)`.

Nested switches (A → B → A within seconds) queue serially through the Completer gate; backend `last_updated_at` (§8.2) resolves row state.

### Full-jitter retry

If `registerDeviceToken` fails and the project retries (typically on `AppLifecycleState.resumed`), randomize the delay over a 0–60s window. Without jitter, every device that was online during a backend outage retries at the same moment when the backend recovers — re-DDoSing it. `nextRetryJitter()` on the cubit returns a `Duration` for this; the retry orchestration lives in the project's `network-creation-supabase` layer.

### `attestationFailed` is terminal

If Firebase App Check rejects the register RPC with an attestation error, the failure is `attestationFailed`. Do NOT retry — the device or build cannot be attested. Surface this as a non-recoverable state in the cubit; the user must reinstall or contact support.

---

## §5 Cold-start deferred dispatch

```
runApp                  RouterReady           Auth+StartupPipeline complete
   │                        │                            │
   ▼                        ▼                            ▼
processInitialMessage()  cubit.onInitialMessage         router.dispatchInForeground
   ↓ post-frame +              listens, calls                ↑
     ~300ms                    router.dispatchInForeground   │
                                       │                    │
                                       ▼                    │
                              navigator ready?              │
                              ├── yes → go()                │
                              └── no  → PendingIntentStore.set(intent)
                                              │
                                              └── replayed once pipeline ready
```

Rule 6: wire BOTH `getInitialMessage` (post-frame + ~300ms) AND `onMessageOpenedApp`. The post-frame delay is empirical — start at 300ms, tune to 500ms if cold-start taps still miss on lower-end devices.

`PendingIntentStore` is a 30-line `ValueNotifier<NavigationIntent?>` ([pending_intent_store.dart](templates/pending_intent_store.dart)). The post-auth pipeline's BlocListener watches it and calls `take()` once the navigator is ready and gating modals are cleared.

### Known gap — tap-after-crash-relaunch

If the app crashes after backgrounding and the user taps a notification, the OS may hand back a fresh Flutter engine. Neither `getInitialMessage` nor `onMessageOpenedApp` fire because the tap predates the new engine.

Default templates do NOT mitigate this. Mitigation is opt-in native payload persistence:
- **iOS:** implement `userNotificationCenter(_:didReceive:withCompletionHandler:)` in `AppDelegate.swift`, persist payload + nav target to App Group `UserDefaults`, read on Flutter launch via `MethodChannel`, clear after dispatch.
- **Android:** read launch `Intent` extras in `MainActivity.configureFlutterEngine` and bridge via `MethodChannel`.

Telemetry on `unknownVariant` rate that spikes after a release without explaining is the canary that pushes a project toward this work.

---

## §6 Payload pattern

Default: Dart 3 native `sealed class NotificationPayload` ([notification_payload.dart](templates/notification_payload.dart)). The Freezed alternative ([notification_payload_freezed_alt.dart](templates/notification_payload_freezed_alt.dart)) exists only for projects already on Freezed.

### Defensive parsing

`fromMessage(FcmMessage)` factory:
1. JSON-encode the data map and reject > 4 KB → `MalformedPayload(reason: 'payload_over_4kb')`. FCM enforces 4096 bytes at the sender (`MessageTooBig`); the client-side guard is defence-in-depth for misbehaving local-test injection.
2. Check `data['type']` is non-empty `String`. Missing/invalid → `UnknownPayload(reason: 'missing_or_invalid_type')`.
3. Dispatch on `type`. Unknown to this app version → `UnknownPayload(reason: 'unknown_type', variantHint: type)`.
4. Required-field validation per variant throws `_MalformedField`, caught and returned as `MalformedPayload`.

### `UnknownPayload` vs `MalformedPayload`

Both are first-class variants. Keep them distinct:
- **Unknown:** type not in our switch. Caused by version skew (sender ahead of installed base).
- **Malformed:** type is known, a required field is missing or wrong-typed. Caused by sender bug.

Telemetry on each lets dashboards tell "we shipped a payload our installed base can't handle" from "the sender's emit got the schema wrong."

### `==` / `hashCode` on every subclass

CRITICAL — `NavigationIntent` flows through `ValueNotifier<NavigationIntent?>` in `PendingIntentStore`, which uses `!=` to decide whether to notify listeners. Default reference equality means two intents-to-the-same-screen are seen as distinct (double-fire) or as identical (never-fire), depending on construction order.

Every concrete subclass in the sealed hierarchy AND `NavigationIntent` itself overrides both. Freezed gets this for free; the native form must hand-write them.

### Unknown-variant UX contract

Router resolves `UnknownPayload` / `MalformedPayload` to `null` intent. Foreground dispatch shows a snackbar ("This update isn't available in your version yet.") and does NOT navigate. Background dispatch only emits telemetry — no UI render in the bg isolate.

NEVER route an unknown payload to home — silently swallowing the tap creates a "the notification did nothing" support burden.

### Payload schema ownership

The set of known `type` values is the contract between app and backend. Maintain a versioned doc in the project (`/docs/notifications/payload-schema.md` or similar). The backend SHOULD include `"min_app_version": "X.Y.Z"` so that payloads requiring features not in the installed base are flagged at parse time and surface as `UnknownPayload` rather than partial routing.

### Localization (two patterns; pick one per project)

**Pattern A — backend translates.** At `register_device_token`, the app sends `locale` (`Locale.toLanguageTag()`). Backend stores per-device. Outgoing FCM uses pre-translated `notification.title` / `notification.body`.
- Pro: works with FCM's `notification` block → iOS/Android system tray "just works" foreground + background + terminated.
- Con: device-language-changed-after-register stays stale until next register. Re-register on `Locale` change to mitigate; otherwise next 7-day heartbeat catches it.

**Pattern B — data-only with i18n key.** Sender ships `{i18n_key, i18n_args}`; client renders against current device locale via the project's ARB.
- Pro: always-current device locale.
- Con: data-only Android foreground-display quirks (relies on Rule 3b path A). Requires client-side ARB completeness; missing keys must fall back to a generic localized title, never the raw key.

Hybrid (translate title for tray, send args for in-app) is possible but adds complexity without clear win.

---

## §7 Router contract

`NotificationRouter` is a pure mapper. It owns payload → `NavigationIntent` mapping and dispatch; it owns NOTHING else.

### Stack-replacing nav

Use `context.go()` (or your router's equivalent — `replaceAll`, `beamToReplacement`, `pushNamedAndRemoveUntil`). Push-based navigation is wrong here:
- Breaks browser back / deep-link callbacks.
- Leaves the prior stack underneath; the user pressing back lands somewhere unexpected.
- Defeats the auth / startup pipeline's stack assumptions (the post-auth shell expects to own the root).

### Modal collision

The dispatcher pops ALL modal routes via `Navigator.of(ctx, rootNavigator: true).popUntil((r) => r.isFirst)` BEFORE navigating. A push tapped while a bottom sheet is open should NOT layer destination under sheet.

### Router is not a permission gate

If a payload routes to a page the user can't access (RLS denial, deactivated feature), the destination page handles the "not found / forbidden" state. Router doesn't try to know what the user is allowed to see — that's a layering violation.

### Unknown payload contract

Snackbar + no navigation. NEVER route-to-home. Routing-to-home silently swallows the tap; the user thinks the app is broken.

### Background dispatch

`dispatchInBackground(payload)` does NOT render UI. It only emits telemetry and writes to `PendingIntentStore`. The next foreground dispatch replays.

---

## §8 Message types & sender contract

### Data-only vs notification messages

See the table in §3. Decision rules:

| Need | Use |
|---|---|
| Tray render with the app terminated (iOS + Android) | `notification` block |
| Foreground custom rendering with full data control | `data` only (or `notification` + `data`) |
| Silent push that does background work without tray render | `data` only + iOS `content-available: 1` |
| Custom Android sound / channel per message | `notification` block with `android.notification.channel_id` |

### Sender-side requirements

| Field | Why |
|---|---|
| Android `priority: "high"` | Required for timely delivery on Doze devices |
| iOS `content-available: 1` | Silent push wake-up |
| iOS `apns-priority: 10` (default) | Foreground display + tray render |
| iOS `apns-priority: 5` | Background-only delivery |

### The legacy `fcm/send` API is dead

Shut down **July 22, 2024**. Any tutorial that references `key=AAAA...` server keys is using the dead API and will return 404. Only the **HTTP v1 API** is live — `POST https://fcm.googleapis.com/v1/projects/<project>/messages:send` with an OAuth2 Bearer token derived from a service-account key.

### 4 KB payload limit

FCM enforces 4096 bytes total per message (notification block + data block + metadata). Practical safe ceiling is ~2 KB once metadata is counted. For richer data, push a reference id in `data`:

```json
{
  "data": {
    "type": "order_shipped",
    "order_id": "abc123",
    "min_app_version": "1.4.0"
  }
}
```

…and fetch the order body via the project's repository on tap. NEVER inline blobs (images, lists, large strings) into `data`.

### Notification grouping

Android: sender's `notification.android.notification.tag` + the client's `setGroup(...)` on `flutter_local_notifications`.
iOS: sender's `apns.payload.aps.thread-id`.

Sender concern primarily. Documented here for visibility; full implementation is project work.

### Backend contract (cross-reference with §8 of the plan)

#### 8.1 RPC shape

```
register_device_token(
  device_id:   String,       // UUID; non-synced; canonical install key
  token:       String,
  platform:    'ios' | 'android',
  user_id:     String,
  app_version: String,       // '1.4.2+87' — for §8.4 min_app_version gating
  os_version:  String,       // 'iOS 17.4' — for min_os_version gating
  locale:      String,       // BCP-47 e.g. 'ro-RO' — for §8.7 Pattern A
) → Future<void or typed-failure>

delete_device_token(device_id, token, user_id) → Future<void or typed-failure>
```

`register_device_token` MUST be **idempotent upsert keyed on `(device_id, user_id)`** — NOT `(user_id, token)`. Token rotation on the same device updates the row; cloud-restored installs with a stale `token` cannot collide with the original device's row.

#### 8.2 Out-of-order writes

Re-login can produce `delete(T)` arriving AFTER `register(T)`. Backend MUST resolve so `register` wins — typically by comparing `last_updated_at` server-side or by ignoring deletes for rows newer than the delete's perceived state.

#### 8.3 Zombie token cleanup

Backend MUST run a TTL reaper. Recommended TTL: **30 days since last `last_seen_at` update**. The app updates `last_seen_at` on register, which fires every 7 days per Rule 4 **regardless of notification-permission state** — a denied-permission user still heartbeats so their row doesn't get reaped (and thus silently miss notifications once they grant later).

Backend MUST handle FCM `UNREGISTERED` / `NOT_FOUND` send errors. Recommended: **7-day soft-delete (tombstone) before hard-delete** — uninstall-reinstall within 7d hits a recoverable row.

#### 8.4 `min_app_version`

For payloads whose `type` was introduced in app version ≥ N, the backend MUST include `"min_app_version": "X.Y.Z"`. Client checks installed version against the floor; below → `UnknownPayload`.

#### 8.5 App Check (out of scope here)

If backend enforces App Check on `register_device_token`, app responds via `<YourProject>Failure.attestationFailed` — terminal for this install; do NOT retry-storm.

#### 8.6 Multi-device tap dedup

FCM's `message_id` is per-send-per-token — fan-out to N devices yields N distinct ids. Backend MUST generate a logical `event_id` (UUID) per logical notification event and include in `data` on every fan-out message. Tap-handler RPC dedups on `(user_id, event_id)`. If "once per device" is required (rare): `(device_id, event_id)`.

#### 8.7 Localization

See §6 — pick Pattern A or B; bake into backend contract.

---

## §9 Permission flow

### Permission states (Rule 7)

```dart
enum NotificationPermissionStatus {
  notDetermined, denied, deniedTerminal, provisional, authorized, ephemeral,
}
```

`deniedTerminal` = `denied` AND `!canPrompt` (the OS won't show another prompt; user must go to Settings).

### Resume-poll pattern

iOS provides no observer for permission revocation. Android 13+ can silently deny. The only reliable detection is polling on `AppLifecycleState.resumed`.

```dart
// Minimal AppLifecycleObserver — bind in your root MaterialApp.
class AppLifecycleObserver extends StatefulWidget {
  final Widget child;
  const AppLifecycleObserver({super.key, required this.child});
  @override
  State<AppLifecycleObserver> createState() => _AppLifecycleObserverState();
}

class _AppLifecycleObserverState extends State<AppLifecycleObserver>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<NotificationsCubit>().refreshFromPermissionState();
    }
  }
  @override
  Widget build(BuildContext context) => widget.child;
}
```

### `deniedTerminal` backoff

Polling on every resume when state will never change wastes cycles. The cubit returns early from `refreshFromPermissionState()` when state is `deniedTerminal`. Soft-reset on `requestPermission()` so a Settings → app return path can re-acquire.

### Soft-ask UX timing

Do NOT call `requestPermission()` on first launch. iOS first-launch deny rate is 60–80%; once denied (terminal-denied on iOS), the path back is Settings only.

Trigger `requestPermission()` when the user takes an action that benefits from notifications (subscribing to a thread, enabling an alert), or after a soft-ask dialog explains why.

### UI gates on permission, NOT registration

`TokenRegistrationStatus.registered` says "we have a token on the server." `NotificationPermissionStatus.authorized` says "the OS will deliver." Either can be true while the other is false. UI gates on permission.

---

## §10 Android channel versioning

Android locks channel importance at creation. Reusing the id with a new importance is a no-op for installed users — the new importance reaches new installs only. User-edited importance overrides (set in Settings) stay per-id; renaming the id resets them.

### Convention

```
<purpose>_v<N>
```

Examples:
- `notifications_v1`
- `chat_v1`, `chat_v2` (after raising chat importance from low to high)
- `marketing_v1`

### Migration (importance change)

1. Increment the version: `notifications_v1` → `notifications_v2`.
2. Update the constant in `FcmTransportImpl` (`_kAndroidDefaultChannelId`).
3. Update the meta-data in `AndroidManifest.xml`.
4. Create the new channel in `_ensureAndroidDefaultChannel()`.
5. Optionally delete the old channel via `AndroidFlutterLocalNotificationsPlugin.deleteNotificationChannel('notifications_v1')`.

### Manifest assertion

Assert that the runtime channel id equals the manifest `default_notification_channel_id`. A mismatch is a silent footgun — system-rendered notifications use the manifest id, app-rendered local notifs use the runtime id, and they diverge in importance.

---

## §11 Testing

### Cubit / router tests

Register `InMemoryFcmTransport` in `setUp`:

```dart
late InMemoryFcmTransport transport;
late NotificationsCubit cubit;

setUp(() {
  transport = InMemoryFcmTransport();
  getIt.registerSingleton<FcmTransport>(transport);
  cubit = NotificationsCubit(transport, repo, deviceIds, router);
});
tearDown(() => getIt.reset());

blocTest<NotificationsCubit, NotificationsState>(
  'dispatches order_shipped to /orders/:id',
  build: () => cubit,
  act: (c) => transport.pushOpened(FcmMessage(
    messageId: 'abc',
    data: {'type': 'order_shipped', 'order_id': '42'},
  )),
  verify: (_) => verify(() => router.dispatchInForeground(any())).called(1),
);
```

The `simulate()` hook on `FcmTransportImpl` is for manual QA panels only — tests use the in-memory transport because it doesn't drag in `firebase_messaging`'s native code paths.

### Router unit tests

One test per payload variant + one for `UnknownPayload` + one for `MalformedPayload`. Assert the resolved `NavigationIntent` and (for the unknown/malformed cases) that no nav was issued.

### Curl template for sender-side testing (HTTP v1)

The Firebase Console "Test send" feature uses a different shape than HTTP v1. The shape your backend actually emits is HTTP v1; test against that.

```bash
ACCESS_TOKEN=$(gcloud auth print-access-token)  # or service-account JWT exchange
PROJECT_ID="<your-firebase-project>"
DEVICE_TOKEN="<the_fcm_token_from_your_device>"

curl -X POST \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  "https://fcm.googleapis.com/v1/projects/$PROJECT_ID/messages:send" \
  -d '{
    "message": {
      "token": "'$DEVICE_TOKEN'",
      "notification": {
        "title": "Test push",
        "body": "Hello from HTTP v1"
      },
      "data": {
        "type": "order_shipped",
        "order_id": "test-123",
        "min_app_version": "1.4.0"
      },
      "android": { "priority": "high" },
      "apns": {
        "headers": { "apns-priority": "10" },
        "payload": { "aps": { "alert": { "title": "Test push" } } }
      }
    }
  }'
```

Notes:
- HTTP v1 disallows nested JSON in `data` — every value is a string. JSON-encode then string-wrap if you need structure.
- The OAuth2 access token is short-lived; for repeat testing, script the JWT exchange from a service-account `.json`.
- Service-account creation: Firebase Console → Project Settings → Service Accounts → Generate new private key.

---

## §12 Pain points & out of scope

### Pain points (lessons learned)

- **Forever-buffered `PendingIntentStore`.** The slot has no TTL by default. A user who taps a notification while unauthenticated and never logs in carries the intent forever. Apply a TTL or clear on auth-state-changed-to-unauthenticated.
- **Android tray cleanup on tap.** If the app handles the tap via `onMessage` foreground render, the system tray entry doesn't auto-dismiss. Call `flutter_local_notifications.cancel(id)` from the tap handler.
- **Modal collision.** Without `popUntil((r) => r.isFirst)`, navigation layers the destination underneath the modal. The dispatcher must pop modals first (§7).
- **OEM background killers (Xiaomi, Huawei, Oppo, Vivo, Samsung).** Aggressive battery savers on these brands kill apps backgrounded for hours, dropping FCM wake-ups. There's no app-side fix. User-facing remediation: "Open Settings → Apps → [app] → Battery → Unrestricted." Provide this copy in your settings page; instrumenting `delivered` rate by manufacturer surfaces the impact.
- **Cold-start delay tuning.** 300ms is the empirical default. On older Android devices or under cold-launch CPU contention, taps still miss. Tune up to 500ms before reaching for native payload persistence.

### Out of scope (explicit)

| Item | Why | Where it would live |
|---|---|---|
| iOS Notification Service Extension (rich media, image attachments) | Native Swift extension; substantial own surface | Future skill: `fcm-rich-notifications` |
| iOS Live Activities / Dynamic Island | Different platform API | Future skill: `ios-live-activities` |
| iOS Critical Alerts / Time-Sensitive | Special entitlement, regulated | Future skill / extension |
| Android Foreground Service | Long-running, not push | Future skill: `android-background-tasks` |
| Multi-device tap-race coordination | Backend concern (idempotent RPCs) | §8.6 |
| Topic subscription / management | Own lifecycle | Future skill |
| In-app notification inbox | UI/UX feature, not transport | Project-level UI |
| Retry/backoff for register RPC | RPC concern, not FCM | `network-creation-supabase` (with §4 jitter note) |
| White-label per-flavor `google-services.json` | Multi-brand build is project-specific | Project-level docs |
| Firebase App Check enforcement | Protects sender, not receiver | Server-side / DevOps |
| Scheduled local notifications (`zonedSchedule`, `USE_EXACT_ALARM`) | Different surface (alarm permissions, doze) | Future skill: `local-scheduled-notifications` |
| CocoaPods iOS dependency manager | Firebase iOS CocoaPods support ends Oct 2026 | Project migration |

---

## §13 Debugging — symptom → cause table

| # | Symptom | Cause | Fix |
|---|---|---|---|
| 1 | `getToken()` returns null in production but works in debug (iOS) | APNs gate skipped or APNs token never bound | Rule 2 — bounded retry on `getAPNSToken()`; transition to `unavailable` not `failed` if it times out |
| 2 | Cold-start tap doesn't fire (terminated-state) | Single-mechanism wiring; or post-frame delay too short | Rule 6 — wire BOTH `getInitialMessage` (post-frame + ~300ms) AND `onMessageOpenedApp`. Tune delay up to 500ms |
| 3 | Foreground notification doesn't appear (Android) | `flutter_local_notifications` not wired; foreground tray render is NOT automatic | Rule 3b — pick path A (re-render via local notif) and thread `messageId` into the payload |
| 4 | Double tap fires (Android) | Both paths A and B wired | Rule 3b — pick ONE. If historical dual-wiring, dedup by `(messageId, 500ms)` |
| 5 | Notification arrives on wrong user after account switch | Logout dissociated by persisted token without comparing to live; or in-flight register completed against old user_id | Rule 5 — `getToken()` first, dissociate by `(device_id, live_token)`. Rule 4 stale-completion drop on `user_id` mismatch |
| 6 | Channel importance change has no effect on existing installs | Android locks importance at channel creation | Rule 8 — version the channel id; bump `_v1` → `_v2` |
| 7 | `setForegroundNotificationPresentationOptions(alert: false)` breaks `onMessage` | Known FlutterFire #17124 / #10804 | Rule 3a — set once at init with `alert: true`; never toggle |
| 8 | Register-storm after backend outage recovers | No jitter on retry; every device retries at the same moment | Rule 4 — full-jitter (0–60s) on the retry; orchestration lives in `network-creation-supabase` |
