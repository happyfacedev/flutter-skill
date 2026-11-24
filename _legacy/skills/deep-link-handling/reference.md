# Deep-Link Handling — Reference

Source files:
- `lib/core/navigation/services/deep_link_service.dart`
- `lib/core/navigation/services/deep_link_parser.dart`
- `lib/core/navigation/services/pending_navigation_store.dart`
- `lib/core/navigation/models/navigation_intent.dart` (the value type)
- `lib/core/router/route_accessibility.dart` (the classification function)

## Dispatch matrix — `RouteAccessibility` × `AuthShell`

When `PendingNavigationStore.submit(intent)` runs, the matrix below decides what happens. `AuthShell` is read from `AuthShellContext.currentShell`.

| Target class | shell = `null` (initial) | shell = `unauthenticated` | shell = `unverified` | shell = `authenticated`, pipeline pending | shell = `authenticated`, pipeline complete |
|---|---|---|---|---|---|
| `publicAlways` | **drop** | drop | drop | drop | drop |
| `onboarding` | **drop** | drop | drop | drop | drop |
| `unauthenticated` | buffer (wait for shell) | **dispatch** | dispatch (still allowed) | drop | drop |
| `unverified` | buffer | drop | **dispatch** | drop | drop |
| `authenticated` | buffer | buffer | buffer | buffer (`_pendingIntent`) | **dispatch** |
| `unknown` | buffer | buffer | buffer | buffer (`_pendingIntent`) | **dispatch** → `RouteNotFoundPage` |

Notes:
- "drop" emits a log line via `dart:developer log`, named `PendingNavigationStore`.
- "buffer (wait for shell)" stashes the intent in `_pendingIntent`. The `_authShellContext.changes` listener calls `_onShellResolved`, which re-evaluates and either dispatches or drops.
- "buffer (`_pendingIntent`)" holds until `markPipelineComplete` is called by `StartupPipelineCubit`. Last-write-wins among multiple submits.
- `unknown` is treated like `authenticated` because dispatching through GoRouter's `errorBuilder` produces a real recovery surface (`RouteNotFoundPage`) instead of a silent no-op.

## URI shape examples

| URI | Parsed location | Notes |
|---|---|---|
| `boilerplate://items` | `/items` | Custom scheme. `uri.host == 'items'`, `uri.path == ''` → reconstructed as `/items` |
| `boilerplate://items/abc/detail` | `/items/abc/detail` | Custom scheme with multi-segment path |
| `boilerplate://items/123/edit?mode=quick` | `/items/123/edit?mode=quick` | Query string preserved |
| `https://app.example.com/items` | `/items` | Universal link |
| `https://app.example.com/items/abc/detail?ref=email` | `/items/abc/detail?ref=email` | Universal link with query |
| `myothersite://items` | (null) | Wrong scheme — rejected |
| `https://malicious.example/items` | (null) | Wrong host — rejected |
| `boilerplate://` | (null) | Empty path |
| `boilerplate:///` | (null) | Empty path (after normalization) |

## Cold-start dedup logic

The need: some versions of `app_links` deliver the cold-start URI through both `getInitialLink()` AND the first `uriLinkStream` event. Without dedup, the user lands on the deeplink target, then immediately gets sent there again (which can interfere with state the destination cubit has built up).

The mechanism:
- `getInitialLink()` result is stashed in `_pendingColdStartDedup` AND handed to `_handleUri` immediately.
- The first stream event matching `_pendingColdStartDedup` is dropped.
- `_pendingColdStartDedup` is cleared on the first stream event REGARDLESS of match. So a different URI arriving as the first stream event clears the dedup state but is itself processed.

Edge cases this catches:
- The cold-start URI is replayed → drop one duplicate, then resume normal stream handling
- The cold-start URI is NOT replayed (newer `app_links` versions) → no-op; first stream event clears state and dispatches normally
- A different URI arrives first via stream → dedup is invalidated (the cold-start one already dispatched), the new URI dispatches normally

Edge case this does NOT handle:
- A user taps the same URI again seconds after launch → that's correctly NOT considered a duplicate (the dedup state has already been cleared). Dispatches normally.

## Buffered-broadcast (`_bufferedDispatches`) explained

Broadcast streams drop events when no listeners are attached. The only `onNavigate` subscriber is `_AppState`'s `initState`, which runs *after* the bloc tree mounts. But `PendingNavigationStore` can dispatch *before* that — e.g., cold-start deeplink dispatches as soon as `PendingNavigationStore.submit` runs during `DeepLinkService.initialize()` (which runs before `runApp`).

The store solves this:
- `_navigationController` is created with `onListen: _flushBufferedDispatches`
- Every `_dispatch` checks `_hasHadListener`. If false, the intent goes into `_bufferedDispatches` instead of the stream.
- When `_AppState` subscribes, `_flushBufferedDispatches` fires (StreamController's `onListen` callback), replays each buffered intent through the stream in arrival order, sets `_hasHadListener = true`.

This makes the produce-then-listen order safe even if `runApp` is reorganized in the future (e.g., eager dispatches added inside `configureDependencies`).

## `_SessionResetBridge` reset triggers

The bridge widget (`lib/bootstrapper.dart`) calls `PendingNavigationStore.reset()` in two cases:

1. **`AuthShell` transitions to `unauthenticated`** (logout):
   ```dart
   if (state.currentShell == AuthShell.unauthenticated) {
     ctx.read<PendingNavigationStore>().reset();
     ctx.read<OrganizationContext>().clearValidated();
     ctx.read<StartupPipelineSessionCache>().clear();
   }
   ```

2. **User-swap** (both ids non-null AND different):
   ```dart
   ctx.read<PendingNavigationStore>().reset();
   ctx.read<OrganizationContext>().clearValidated();
   ctx.read<StartupPipelineSessionCache>().clear();
   ```

The user-swap case guards against future flows that switch users without going through `unauthenticated` (account switcher, backend session refresh that returns a different user). No flow does this today, but the bridge is defensive.

## Cross-scheme deeplink fallback (in `router.dart`)

If a `boilerplate://` URI somehow reaches the router directly (rare — usually `DeepLinkService` captures it first), the router's `handleRedirect` has a pre-handler that reconstructs the path from `uri.host` + `uri.pathSegments` and reroutes to it — but ONLY if the current `AuthShell` can reach it. Otherwise falls through to the default path-based redirect.

This is the "belt-and-suspenders" layer that catches edge cases where `app_links` delivers a URI directly to the router instead of through `DeepLinkService`. See `lib/core/router/router.dart` lines ~120-156.

## Debugging steps

When a deeplink doesn't navigate as expected, run through these in order:

1. **Is the URI captured?** Check console for `DeepLinkService` log lines:
   - "Submitting deep link: …" — service captured + parsed + submitted
   - "Ignoring unrecognized URI: …" — parser rejected (wrong host/scheme)
   - "Failed to get initial deep link" — cold-start `getInitialLink` threw
   - (Nothing) — `initialize()` didn't run, or app wasn't actually launched by the URI

2. **Is the URI parsed correctly?** Test `DeepLinkParser.parse(uri, validHost: ..., validScheme: ...)` in a unit test or REPL — the output `NavigationIntent.location` must start with `/` and have the shape `AppRoutes` expects.

3. **Is the host/scheme configured?** `DeepLinkService` passes `EnvConfig.deepLinkHost` / `EnvConfig.customScheme` to the parser. If they're left as placeholders (or don't match the URI), the parser drops the URI. These are static getters populated by `EnvConfig.initialize()` at the start of `bootstrap()`, so they're always available — confirm they match the scheme/host you're testing with.

4. **Is the target class correct?** Check `PendingNavigationStore` log lines:
   - "Dropping publicAlways / onboarding deeplink target: …" — the target is system-only, route should be a different one
   - "Dropping unauthenticated deeplink — current shell authenticated: …" — user is logged in but target requires logged-out
   - (No log line) — buffered or dispatched

5. **Is the pipeline complete?** If `authenticated`-class target dispatched but the user is still on the spinner, `markPipelineComplete` hasn't fired. Check `StartupPipelineCubit` — likely a step is failing or not reporting completion.

6. **Is the dispatch reaching the router?** Check `PendingNavigationStore` logs:
   - "Dispatching to stream: …" — store dispatched, `_AppState` listener should have received
   - "Dispatch buffered (no listener yet): …" — happened before `_AppState` subscribed; will replay on subscribe
   - (Nothing) — store didn't dispatch; check classification + shell

## Simulator / device commands

| Platform | Command | URI form |
|---|---|---|
| iOS Simulator | `xcrun simctl openurl booted boilerplate://items` | Custom scheme |
| iOS Simulator | `xcrun simctl openurl booted https://app.example.com/items` | Universal link |
| Android Emulator | `adb shell am start -W -a android.intent.action.VIEW -d "boilerplate://items"` | Custom scheme |
| Android Emulator | `adb shell am start -W -a android.intent.action.VIEW -d "https://app.example.com/items"` | Universal link |
| Cold-start test | Kill the app first (swipe up / `adb shell am force-stop`) before running the open command | Either |
| Warm-start test | Leave the app foregrounded, run the open command | Either |
