---
name: fcm-notifications
description: |
  Implements end-to-end Firebase Cloud Messaging (FCM) in Flutter:
  transport service (singleton + streams + background handler), token
  lifecycle (register / refresh / delete / coalesce / reconcile),
  cold-start tap dispatch, foreground display wiring, typed sealed
  payloads, payload-to-navigation routing, permission flow with
  resume-poll, Android channel versioning, platform setup. Use when
  the user mentions FCM, Firebase Messaging, push notification, APNs,
  notification token, onTokenRefresh, getInitialMessage,
  onMessageOpenedApp, background message handler, notification channel,
  foreground notification, notification tap, or deep link from a push.
  Cubit shape → cubit-creation; model shape → model-creation;
  repository → network-creation-supabase; failures → failure-modeling.
---

# FCM Notifications

> **Boilerplate note:** The live FCM / Firebase code (firebase_messaging, Firebase Cloud Messaging, Crashlytics, Analytics) is **NOT** present in this boilerplate — it was removed. This skill is kept as a reference pattern for when you add push notifications back; nothing here is wired into the app today, and you would also need to add the Firebase dependencies + native setup yourself.

The standard FCM shape is: an abstract `FcmTransport` exposing three broadcast `Stream<FcmMessage>` (foreground / opened / initial) + token APIs, backed by an `@Singleton` `FcmTransportImpl` that adapts `RemoteMessage → FcmMessage` so nothing outside the impl imports `firebase_messaging`. A `NotificationsCubit` (`@singleton` `HydratedCubit`) subscribes to those streams, owns token lifecycle (coalesced register/refresh/delete reconciled against a persisted snapshot), maps payloads through a pure `NotificationRouter` to a stack-replacing nav primitive, and runs a resume-poll on permission state. Tests inject `InMemoryFcmTransport` instead of mocking firebase_messaging.

This skill owns the FCM-specific *contracts* (coalescing rules, cold-start dual mechanism, foreground-display wiring, payload discriminator pattern, Android channel versioning, backend payload contract). It delegates *shape* to sibling skills:

- **Cubit / state class structure** → `cubit-creation`
- **Sealed-union model with `fromMessage` factory** → `model-creation`
- **Repository for `register_device_token` / `delete_device_token`** → `network-creation-supabase`
- **`<Feature>Failure` hierarchy + ARB keys** → `failure-modeling`
- **`bloc_test` against `InMemoryFcmTransport`** → `unit-testing`

When you need that shape, invoke the sibling — do not restate its rules here.

## Pinned versions

| Package | Floor | Notes |
|---|---|---|
| `firebase_messaging` | ≥ 16.1.1 | 16.1.0 briefly re-introduced an iOS-18 duplicate-notification regression; 16.1.1 re-fixed it. 16.1.0 also added UISceneDelegate support but that path is still maturing — default to UIApplicationDelegate. |
| `flutter_local_notifications` | ≥ 21.0.0 | v22 is in prerelease (Android 16); not stable yet. |
| Flutter SDK | ≥ 3.38.0 | Floor for iOS 26 + Xcode 26. |
| iOS deployment target | ≥ 13.0 | Required by `firebase_messaging` 15+. |
| Android `compileSdk` | 35 | Aligns with current FCM targets. |
| Xcode | ≥ 26.0 | Required for iOS 26 SDK. |
| iOS dependency manager | SPM (recommended) | Firebase iOS SDK CocoaPods support ends October 2026. |

## Critical Rules (Never Break)

### Rule 1 — Background handler is top-level + `@pragma('vm:entry-point')` + Firebase-init-first + registered pre-`runApp`

The background-message handler MUST be a top-level (or `static`) function annotated `@pragma('vm:entry-point')`, calling `await Firebase.initializeApp()` as its first line, registered via `FirebaseMessaging.onBackgroundMessage(...)` BEFORE `runApp()`.

**Never:** wire it from inside a widget, `initState`, or any class method. Never skip `@pragma`.

**Why:** `@pragma('vm:entry-point')` keeps the function alive through tree-shaking in release builds (Flutter 3.3+). The handler runs in a separate isolate without Firebase initialized — the init call is mandatory. Registering after `runApp` silently no-ops on cold-start messages because the handler is wired too late.

### Rule 2 — iOS APNs gate before `getToken()`

On iOS, await `FirebaseMessaging.instance.getAPNSToken()` (bounded retry: ~3s with 300ms backoff) before any other FCM call. If the APNs token never arrives, mark the service `unavailable` — NOT `failed` — and do not mint an FCM token.

**Never:** call `getToken()` on iOS before APNs is bound. Never treat missing APNs as fatal — it's expected on simulators and on devices without push entitlement.

**Why:** iOS FCM SDK ≥ 10.4 requires the APNs token before FCM token issuance. Without the gate, `getToken()` may return `null` silently in release/TestFlight builds — passes in debug, breaks in production.

### Rule 3 — Foreground display: one path per platform, no dynamic toggling

**3a (iOS):** Call `FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true)` once during init. Do NOT toggle dynamically — FlutterFire #17124 / #10804 show that `alert: false` can suppress `onMessage` delivery as well as display.

**3b (Android):** Foreground display is NOT automatic. Wire `flutter_local_notifications`. Pick exactly ONE tap path:
- **(A)** `onMessage` re-displays via local notifications; `onDidReceiveNotificationResponse` handles taps. **Requires** serializing `messageId` into the local-notif payload (`payload: jsonEncode({'messageId': msg.messageId, 'data': msg.data})`) so dedup against `onMessageOpenedApp` works on a 500ms window.
- **(B)** `onMessage` displays only; tap arrives via `onMessageOpenedApp` (requires sender to include `notification` block).

Never wire both paths — duplicate tap fires. If a project has historical dual-wiring, dedup by `(messageId, 500ms)` using the threaded key.

**Why:** iOS suppresses tray display in foreground by default. Android suppresses tray display in foreground unconditionally. The local-notification callback has no access to the originating `RemoteMessage` — the bridge is the serialized payload string. 500ms window absorbs legitimate same-second user re-taps.

### Rule 4 — ALL token-register paths funnel through one Completer gate

Every register trigger — explicit `refreshToken()`, `onTokenRefresh` stream event, permissions-granted callback, post-attestation retry — awaits a single `Completer<void>?` held by the controller. Concurrent triggers await the in-flight future instead of firing parallel RPCs.

Register only when **live token ≠ persisted** OR **`now − lastRegisteredAt > 7 days`**. The 7-day heartbeat fires regardless of permission state — a denied-permission user still pings so `last_seen_at` refreshes and §8.3 zombie-cleanup doesn't reap their row.

The in-flight RPC runs under a bounded timeout (15–30s). On timeout or failure, the controller calls `completer.completeError(failure)`; awaiting callers `try/catch` around the `await`. The gate unwedges on every outcome — never on success alone.

**Stale-completion drop.** The in-flight future carries `(token, user_id, device_id)`. When it resolves, the controller drops the result if ANY:
- `user_id != currentUserId` (user switched mid-flight)
- `currentUserId == null` (auth not yet hydrated; null mismatch must NOT default-pass)
- `live FCM token ≠ in-flight token` (a fresher `onTokenRefresh` arrived; new caller starts its own registration)

**Never:** fire `registerDeviceToken` from a stream listener without the gate. Never re-register on every cold start when nothing changed. Never let an awaited Completer hang on a stalled RPC.

**Why:** at sign-in, auth-state-change + `onTokenRefresh` + permission-grant can fire in the same tick. Without the gate, three concurrent RPCs race. Register-every-cold-start is wasted RPCs at scale (50k DAU = 50k no-op writes/day). The triple-axis stale drop closes the layering smell: backend `last_updated_at` resolves row state, but the app still needs to know which Completer the awaiter is actually waiting on.

### Rule 5 — Logout reconciliation by `(device_id, live_token)`, never by persisted token alone

Every register/delete RPC carries `(device_id, token, user_id)`. `device_id` is a UUID generated on first launch and persisted in **non-synced** storage (iOS Keychain with `kSecAttrSynchronizable: false`; Android non-backup cache dir) — NOT eligible for iCloud / Android Auto Backup.

On logout: call `getToken()` FIRST to fetch the live token. If `live ≠ persisted`, dissociate by `(device_id, live_token)`. Then `deleteToken()` (FCM-side) and clear persisted state. If the dissociate RPC fails, persisted state STILL clears; logout UX never blocks on the RPC. The orphan is reaped by §8.3 TTL.

**Account switching** runs the same reconciliation. Expose `onUserChanged(newUserId)`; do NOT special-case as "skip reconciliation."

**Caller location.** `onUserChanged` is invoked from the composition root (`lib/bootstrapper.dart` via `BlocListener<AuthCubit, AuthState>` calling `ctx.read<NotificationsCubit>().onUserChanged(...)`). This is the parent-widget `BlocListener` path (option a) of `cubit-creation` Rule 5 — NOT a cubit-to-cubit call.

**Never:** dissociate by *persisted* token without comparing to live. Never block logout on the RPC. Never add a `pendingDeletion` flag — breaks "logout always succeeds." Never key a register/delete by `token` alone — always pair with `device_id`.

**Why:** cloud restore (iOS iCloud Keychain, Android Auto Backup) can hydrate a token from another device. Keying off `(device_id, token)` instead of `(token)` means a restored install cannot dissociate the *original* device's still-live backend row, even if `getToken()` briefly returns the cached value before FCM rotates. TTL cleanup is asynchronous; brief orphans are cheaper than synchronous multi-device coordination (impossible from the app).

### Rule 6 — Cold-start dual mechanism: `getInitialMessage` + `onMessageOpenedApp`

Wire BOTH `getInitialMessage` (post-frame deferred, with a short empirical delay — start at 300ms, tune per project) AND `onMessageOpenedApp` (fallback listener). Single-mechanism wiring is not sufficient.

**Never:** rely on `getInitialMessage` alone — historical FlutterFire issues #9906 / #10737 / #12172 documented it returning `null` on iOS terminated taps. All three are now closed, but user reports of the underlying timing behavior continued through 2025. Defensive double-mechanism is still best practice.

**Why:** the 300ms post-frame delay is an empirical default, not a value cited in the upstream issues. Tune up to ~500ms if cold-start taps still go missing on lower-end devices. `onMessageOpenedApp` is the fallback when `getInitialMessage` still misses; together they cover the full terminated-state-tap surface.

**Known gap — tap-after-crash-relaunch.** If the app crashes after backgrounding, then the user taps and the app cold-launches into a fresh process, neither mechanism may fire. Default templates do NOT mitigate this; projects that observe the symptom in telemetry can opt in to native-side payload persistence (iOS `userNotificationCenter(_:didReceive:)` + App Group `UserDefaults`; Android `MainActivity` Intent extras via `MethodChannel`).

### Rule 7 — Permission state is polled, never inferred from token presence

The controller exposes:

```dart
Future<NotificationPermissionStatus> refreshFromPermissionState();

enum NotificationPermissionStatus {
  notDetermined, denied, deniedTerminal, provisional, authorized, ephemeral,
}
```

It mutates state AND returns the resolved status so callers (`onPressed`, deep-link gates) can branch synchronously without an extra rebuild. A widget (e.g. `AppLifecycleObserver`) invokes it on `AppLifecycleState.resumed`. UI gates visible features on permission state, NOT on `registrationStatus`. When state is `deniedTerminal` (`denied` AND `!canPrompt`), the poll backs off to at-most once per app-foreground session.

**Permission UX timing:** soft-ask in-app BEFORE the OS prompt. Do NOT trigger `requestPermission()` on first launch; trigger when the user takes an action that benefits from notifications, or after a soft-ask dialog explains why.

**Never:** infer permission state from "we have a token, so we're good." Never call `requestPermission()` on app first-open without context. Never poll `refreshFromPermissionState()` on every resume when state is terminal-denied — wastes cycles, result never changes.

**Why:** iOS provides no observer for permission revocation. Android 13+ silently denies. Token presence + denied permission = silent feature breakage. Polling on resume is the only reliable cross-platform detection of state change. First-launch OS prompt has a documented 60–80% deny rate on iOS; soft-asking first inverts that.

### Rule 8 — Android channel ids are versioned for importance

Version channel ids: `<purpose>_v<N>`. NEVER change importance on an existing channel id. To change importance, increment the version (`notifications_v1` → `notifications_v2`).

**Never:** ship a notification on `channel_v1` with `Importance.high` after previously shipping `channel_v1` with `Importance.low`. Never reuse a channel id across an importance migration.

**Why:** Android locks notification channel importance at creation. Reusing the id with a new importance is a no-op for installed users — the new importance reaches new installs only. Versioned ids force the recreation that surfaces the issue at code-review time. User-edited importance overrides (set in Settings) stay per-id; renaming resets the override.

## Templates

Replace `your_app` (package name) and any example payload variants with project-specific values.

- [fcm_message.dart](templates/fcm_message.dart) — Firebase-free DTO; the type on every transport stream and on `payload.fromMessage(...)`
- [fcm_transport.dart](templates/fcm_transport.dart) — abstract interface (three streams + token APIs)
- [fcm_transport_impl.dart](templates/fcm_transport_impl.dart) — `@Singleton(as: FcmTransport)` production impl; only file that imports `firebase_messaging`
- [in_memory_fcm_transport.dart](templates/in_memory_fcm_transport.dart) — test double with `pushForeground/pushOpened/pushInitial`
- [notification_payload.dart](templates/notification_payload.dart) — Dart 3 `sealed class` with `==`/`hashCode`, `fromMessage` factory, distinct `UnknownPayload` vs `MalformedPayload`
- [notification_payload_freezed_alt.dart](templates/notification_payload_freezed_alt.dart) — Freezed alternative for projects already on Freezed
- [notifications_state.dart](templates/notifications_state.dart) — manual `copyWith` state (token + permission only); no Freezed
- [notifications_cubit.dart](templates/notifications_cubit.dart) — `@singleton` `HydratedCubit` owning token + permission state; private-field Completer / dedup map / current-user
- [notification_router.dart](templates/notification_router.dart) — pure mapper; `dispatchInForeground` (modal pop + `go()`) vs `dispatchInBackground` (telemetry + buffer; no UI)
- [pending_intent_store.dart](templates/pending_intent_store.dart) — `ValueNotifier<NavigationIntent?>` deferred-dispatch buffer
- [android_manifest_snippet.xml](templates/android_manifest_snippet.xml) — `POST_NOTIFICATIONS`, default channel id, default icon + color
- [ios_setup_checklist.md](templates/ios_setup_checklist.md) — capabilities, entitlements, APNs key, SPM, lifecycle decision

## Reference

See [reference.md](reference.md) for:
- §1 Platform setup & greenfield checklist (Firebase project, APNs `.p8`, Xcode 26 capabilities, ProGuard, SPM vs CocoaPods, AppDelegate vs SceneDelegate, Flutter ≥ 3.38)
- §2 `FcmTransport` anatomy (streams, init lifecycle including init-failure path, `simulate()` dev hook, telemetry observer)
- §3 Background + foreground display (background-isolate plugin constraints table, data-only vs notification messages, iOS silent-push budget, tap dedup)
- §4 Token lifecycle (register / refresh / delete / coalesce, persisted reconciliation, 7-day heartbeat, full-jitter retry, App Check `attestationFailed`)
- §5 Cold-start deferred dispatch (`PendingIntentStore` reference impl)
- §6 Payload pattern (`sealed class` default; defensive parsing; `UnknownPayload` vs `MalformedPayload`; 4 KB limit; localization Patterns A & B)
- §7 Router contract (stack-replacing nav, modal pop, unknown = snackbar + no nav)
- §8 Message types & sender contract (data-only vs notification; legacy `fcm/send` API is dead; HTTP v1 only; `event_id` for multi-device dedup)
- §9 Permission flow (provisional iOS, Android 13+, resume-poll, soft-ask timing, terminal-denied backoff)
- §10 Android channel versioning
- §11 Testing (`InMemoryFcmTransport`, router unit tests, HTTP v1 curl)
- §12 Pain points & out of scope (OEM background killers, forever-buffered intent TTL)
- §13 Debugging — symptom → cause table for the top 8 reported FCM failures

## Checklist

- [ ] Background handler is `@pragma('vm:entry-point')`-annotated, top-level, calls `Firebase.initializeApp()` first, registered before `runApp()`.
- [ ] iOS APNs gate (`getAPNSToken()` with 3s/300ms retry) precedes the first `getToken()` call.
- [ ] iOS `setForegroundNotificationPresentationOptions(alert: true, ...)` is called once at init; never toggled at runtime.
- [ ] Android foreground display goes through `flutter_local_notifications`; exactly one tap path wired (A or B, not both); **`messageId` is serialized into the local-notif `payload` JSON** so `onDidReceiveNotificationResponse` can dedup against `onMessageOpenedApp` on the 500ms window.
- [ ] All token-register call sites funnel through the single `Completer<void>?` gate with a bounded timeout (15–30s). On timeout/failure the controller calls `completeError(failure)`; callers `try/catch`. Register-gate (live ≠ persisted OR > 7d) prevents register-every-cold-start. The 7-day heartbeat fires regardless of permission state.
- [ ] In-flight register futures carry `(token, user_id, device_id)`. The controller drops completions where `user_id != currentUserId` OR `currentUserId == null` (auth not hydrated) OR `in-flight token ≠ live token`.
- [ ] Every register/delete RPC carries `device_id` (non-synced UUID; Keychain `kSecAttrSynchronizable: false` on iOS, non-backup cache dir on Android). Backend keys `(device_id, user_id)`, NOT `(user_id, token)`.
- [ ] Logout / `onUserChanged` calls `getToken()` first; dissociates by `(device_id, live_token)`; does not block on RPC. `onUserChanged` is invoked from `bootstrapper.dart` via `BlocListener<AuthCubit, AuthState>` — NOT from inside another cubit.
- [ ] Cold-start uses BOTH `getInitialMessage` (post-frame + ~300ms) AND `onMessageOpenedApp`. Tap-after-crash-relaunch gap acknowledged; native-side payload persistence is opt-in.
- [ ] Permission flow: `refreshFromPermissionState()` returns typed `Future<NotificationPermissionStatus>` AND mutates state; invoked on `AppLifecycleState.resumed`; `deniedTerminal` backoff in place; `requestPermission()` is NOT called on first launch (soft-ask first).
- [ ] Channel ids are `<purpose>_v<N>`; never reused for an importance change. AndroidManifest declares `default_notification_icon` + `default_notification_color` + `default_notification_channel_id`; does NOT manually declare `FirebaseMessagingService`.
- [ ] Payload sealed union (Dart 3 native `sealed class` by default; Freezed only if project already on Freezed) **overrides `==` and `hashCode` on every concrete subclass and on `NavigationIntent`** (else `ValueNotifier`-based `PendingIntentStore` dedup breaks). Has a first-class `UnknownPayload` AND a distinct `MalformedPayload`; defensive parsing covers type-checks + `tryParse`; rejects payloads > 4 KB defensively; telemetry-emit on each.
- [ ] `FcmMessage` DTO is the type on every `FcmTransport` stream and on `payload.fromMessage(...)`. `RemoteMessage` is referenced ONLY inside `FcmTransportImpl`.
- [ ] Init failure routes through `addError(NotificationsInitFailure(e), st)` → `AppBlocObserver`. Cubit code never calls Crashlytics directly.
- [ ] Cubit state class contains TokenRegistrationState + PermissionState only. `Completer`, `_recentTaps`, `_currentUserId`, `_inFlightTokenSnapshot` are **private cubit fields, NOT in state, NOT in `toJson`**. Cubit file ≤ 300 lines.
- [ ] Router uses the stack-replacing primitive; dispatcher pops modals before navigating. `dispatchInBackground` does NOT render UI (no snackbar / dialog from bg isolate).
- [ ] Backend contract (§8): `(device_id, user_id)` idempotent upsert; TTL ≥ 30d with heartbeat-regardless-of-permission; UNREGISTERED handled with 7d soft-delete tombstone; `event_id` (not FCM `message_id`) for multi-device dedup; `min_app_version` MUST for type-versioned payloads; localization Pattern A or B picked deployment-wide per §8.7.
- [ ] `FcmTelemetryEvent` carries `dispatchLatencyMs` for `opened` / `navigated` events.
- [ ] iOS setup: lifecycle decision (AppDelegate or SceneDelegate); SPM unless mid-migration; Flutter ≥ 3.38; Xcode ≥ 26. `aps-environment` = `development` for Xcode Run, `production` for Ad Hoc / TestFlight / App Store.
- [ ] Android: `onBackgroundMessage` displays local notification only — no Activity start (API 31+ restriction). Routing happens after user-tap via `getInitialMessage` / `onMessageOpenedApp`.
