---
name: deep-link-handling
description: The deep-link pipeline — `DeepLinkService` (captures URIs via `app_links`, both cold-start and warm-stream, with cold-start dedup) → `DeepLinkParser` (validates host/scheme against `EnvConfig.deepLinkHost` / `EnvConfig.customScheme`, normalizes URI into a `NavigationIntent`) → `PendingNavigationStore` (routes the intent via `RouteAccessibility` + current `AuthShell`; buffers authenticated-class targets until pipeline complete; drops invalid-shell or system-only targets; dispatches via broadcast `Stream<NavigationIntent>` consumed by `_AppState`). Covers initialization ordering (`DeepLinkService.initialize()` MUST run before `runApp` to capture cold-start URIs), env-driven host/scheme validation (no tenant/`OrganizationContext` dependency in the infra layer), the shared-store pattern (any external navigation trigger uses the same `PendingNavigationStore`), the `markPipelineComplete` contract (always dispatches — home as fallback when no pending intent), per-session reset on logout/user-swap, and the buffered-broadcast pattern for handling pre-listener dispatches. Use when adding a new deeplinkable target, debugging "tap on link doesn't navigate", debugging "cold-start link lost", adding deeplink support to a new feature, configuring `deepLinkHost` / `customScheme`, or when the user mentions "deep link", "deeplink", "deep-link", "app_links", "universal link", "custom scheme", "boilerplate://", "DeepLinkService", "DeepLinkParser", "PendingNavigationStore", "NavigationIntent", "cold-start dispatch", or "deferred navigation". Adding the route the deeplink lands on → /navigation-gorouter. Where deepLinkHost / customScheme are declared → /env-config-flavors. Composition-root registration of DeepLinkService → /bootstrap-composition-root.
argument-hint: "[feature-or-uri]"
---

# Deep-Link Handling

The deep-link pipeline is **a three-stage pipeline** with one shared output sink:

```
app_links package          → DeepLinkService    (capture: cold-start + warm-stream + dedup)
                             ↓ Uri
                           → DeepLinkParser     (validate host/scheme; normalize to NavigationIntent)
                             ↓ NavigationIntent
                           → PendingNavigationStore  (buffer / drop / dispatch by RouteAccessibility + AuthShell)
                             ↓ Stream<NavigationIntent>
                           → _AppState listener  (calls router.go(intent.location))
```

`PendingNavigationStore` is designed to be the **single navigation arbiter for any external-trigger intent**. Deep links are the one producer wired in the boilerplate; any other external trigger you add later (for example a push-notification tap — see `/fcm-notifications` for that pattern, which is documented but not wired in by default) submits intents to the same store the same way.

The system runs once and stays running for the app's lifetime. Most "I want to add deeplink support" tasks don't actually require touching this skill — they require adding a route via `/navigation-gorouter`, and the existing pipeline picks it up automatically. This skill is for when you need to understand *why* a deeplink does or doesn't navigate, or when you're configuring the host/scheme.

## Critical Rules (Never Break)

1. **`DeepLinkService.initialize()` MUST run before `runApp` in `shared_main.dart`.** *Why:* cold-start URIs (the app launched from a terminated state via a link) are returned once by `app_links.getInitialLink()`. If initialization happens after `runApp`, the splash screen has already mounted and the pipeline can complete before the URI is captured — the user lands on home instead of the deeplinked page. The current `shared_main.dart` runs it as the second-to-last step before `runApp`; preserve that.

2. **NEVER call `Router.of(context).go(...)` directly from `DeepLinkService` or anywhere outside `_AppState`.** *Why:* the store has no router reference by design. Navigation is a one-shot side effect; producers (`DeepLinkService`, and any future external-trigger producer) submit intents to the store, the store dispatches via broadcast stream, and `_AppState` is the single subscriber that calls `router.go`. This decouples the producers from the router lifecycle (the router is rebuilt on auth changes; producers shouldn't have to know).

3. **Host + scheme come from `EnvConfig` (`deepLinkHost`, `customScheme`), and `DeepLinkService` takes no tenant dependency.** *Why:* `DeepLinkService` is an infra-layer service — it must not depend on `OrganizationContext`, `OrganizationCubit`, or any tenant state. The values are static getters on `EnvConfig`, populated by `EnvConfig.initialize()` at the very start of `bootstrap()`, so they are always available by the time any URI arrives. `_handleUri` passes them per call: `DeepLinkParser.parse(uri, validHost: EnvConfig.deepLinkHost, validScheme: EnvConfig.customScheme)`.

4. **`DeepLinkService` is `@singleton`.** *Why:* it owns the process-lifetime `app_links.uriLinkStream` subscription; a second instance would produce duplicate `submit(...)` calls for every URI. This is one of the rare app-lifetime singletons that requires explicit user approval (see `/bootstrap-composition-root` rule 2) — and approval has already been granted via the `@singleton` annotation in `deep_link_service.dart`.

5. **`PendingNavigationStore.submit` validates and classifies — never bypass it.** *Why:* `submit` runs `assert(intent.location.startsWith('/'))` (fail-fast at the producer) and `classifyLocation` (drop publicAlways/onboarding targets; route authenticated-class targets through the pipeline buffer; check shell reachability for unauth/unverified targets). Calling `_dispatch` directly from a producer skips all of that and produces hard-to-trace navigation bugs.

6. **`markPipelineComplete` ALWAYS dispatches** — home if no pending intent. *Why:* the pipeline page is sitting on a loading spinner waiting for navigation; if `markPipelineComplete` short-circuits when nothing is pending, the user is stranded. The contract is "after pipeline completes, the user lands somewhere" — and that fallback is home. This must hold for re-entries within the same session (e.g., the pipeline cubit re-runs because a substep redirected back) — see the unit test `re-entering after first completion dispatches again` in `pending_navigation_store_test.dart`.

## The pipeline in detail

### 1. Capture — `DeepLinkService`

`initialize()` does two things:

1. **Cold-start:** `appLinks.getInitialLink()` returns the URI that launched the app (or null). If non-null, the service hands it to `_handleUri` AND stashes it in `_pendingColdStartDedup`.
2. **Warm-start:** `appLinks.uriLinkStream.listen(...)` subscribes for future links. The first event matching `_pendingColdStartDedup` is dropped (some `app_links` versions deliver the cold-start URI again through the stream); every subsequent event is processed.

`_pendingColdStartDedup` clears on the first stream event regardless of match — so repeat-taps of the same URI dispatch normally.

`dispose()` cancels the subscription. Called by GetIt's `@disposeMethod` on the rare cases the singleton actually disposes (test cleanup, hot-restart in dev).

### 2. Parse — `DeepLinkParser`

`DeepLinkParser.parse(uri, validHost: ..., validScheme: ...)` returns a `NavigationIntent` or null.

Validation logic:
- If `uri.scheme == validScheme` (case-insensitive) → accept
- If `uri.scheme == 'https' && uri.host == validHost` (case-insensitive) → accept
- Otherwise → return null

Normalization logic (the tricky part):
- For custom-scheme URIs (`boilerplate://items/...`), `app_links` parks the first path segment in `uri.host`. The parser reconstructs the full path as `/${uri.host}${uri.path}`.
- For universal links (`https://app.example.com/items/...`), `uri.path` already has the right shape.
- Trailing slashes are stripped. Empty paths return null.
- Query string is preserved (so `mode=edit`, `ref=email`, etc. flow through to the eventual route handler).

Result: a `NavigationIntent` whose `.location` is an absolute path the router can handle directly.

### 3. Route — `PendingNavigationStore.submit`

This is where most of the logic lives. `submit(intent)`:

1. Asserts `intent.location.startsWith('/')` — catches malformed intents at the producer.
2. Classifies via `classifyLocation(intent.location)` → `RouteAccessibility` enum:
   - `publicAlways` (splash, verificationComplete, forceUpdate) → **drop** (never a valid deeplink target)
   - `onboarding` (startup pipeline + its steps) → **drop** (pipeline owns these)
   - `unauthenticated` (intro, landing, login, …) → **shell-gated**: dispatch if current shell allows it; buffer until shell resolves; drop if past it
   - `unverified` (email-verified) → **shell-gated**: same logic
   - `authenticated` (everything else declared) → **buffer until pipeline complete**, then dispatch
   - `unknown` (path doesn't match any `AppRoutes`) → treated as `authenticated` so GoRouter's `errorBuilder` renders `RouteNotFoundPage`

3. Dispatches the resulting intent (immediately or eventually) via the broadcast `onNavigate` stream.

### 4. Dispatch — `_AppState`'s listener

`_AppState` (in `lib/app.dart`) subscribes once to `store.onNavigate` and calls `router.go(intent.location)` on every event. Late subscriptions matter: the store buffers dispatches that arrive before the first listener attaches and replays them on subscribe. Real-world: cold-start URI captured at `DeepLinkService.initialize()` runs *before* `_AppState`'s subscription, so the buffered-broadcast pattern is what makes cold-start navigation work.

### Per-session reset

On logout or user-swap, `_SessionResetBridge` calls `PendingNavigationStore.reset()` — clears `_pendingIntent` and `_pipelineComplete = false`. Without this, a logged-out user's pending deeplink would survive across sessions and dispatch when the next user signs in, which is the wrong contract.

## Adding deeplink support to a feature

In ~95% of cases the answer is: **add the route via `/navigation-gorouter`** and you're done. As long as the route's path matches what your deeplink emits (e.g., `boilerplate://items/123` → `/items/:id` route), the existing pipeline routes it.

The flow:

1. Add `AppRoutes.<name>` enum entry with the path (see `/navigation-gorouter`)
2. Add the `GoRoute` definition (see `/navigation-gorouter`)
3. (If the route is authenticated) — automatic, the store buffers until pipeline complete
4. (If the route is unauthenticated like `/landing`) — also automatic, the store dispatches if the current shell is `unauthenticated`
5. Test with `xcrun simctl openurl booted boilerplate://...` or platform equivalents

### Host + scheme config

The associated-domain host and custom scheme are declared on `EnvConfig`:

```dart
static String get deepLinkHost => 'app.example.com';
static String get customScheme => 'boilerplate';
```

`DeepLinkService` reads these and passes them to the parser; if a URI doesn't match either, the parser returns null and the URI is ignored. Change them to your own associated domain + scheme. See `/env-config-flavors`.

The native side also needs configuration:
- **iOS**: `Info.plist` Universal Links + AASA file hosted at the domain
- **Android**: `AndroidManifest.xml` `<intent-filter>` for the custom scheme + auto-verify for the universal link host

Those native steps are out of scope for this skill — they're standard `app_links` setup.

## Cold-start vs warm-start — both work

The cold-start path (`getInitialLink`) and warm-start path (`uriLinkStream`) feed the same `_handleUri`, which submits the same shape of intent to the store. From the consumer's perspective there's no difference — that's the design.

What *is* different is **timing**:
- Cold-start: URI captured *before* `runApp`. Pipeline hasn't completed yet. The store buffers the intent. When the user signs in (or already-signed-in's pipeline completes), `markPipelineComplete` dispatches it.
- Warm-start: URI arrives mid-session. If authenticated and past the pipeline, immediate dispatch. If on landing/login, shell-gated logic decides.

## What this skill does NOT cover

- **The route the deeplink lands on** — declared via `AppRoutes` + `GoRoute`, see `/navigation-gorouter`
- **The page widget rendered at that route** → `/page-creation`
- **`EnvConfig.deepLinkHost` / `customScheme` declaration** → `/env-config-flavors` (where the values live)
- **Push-notification tap-to-navigate** — would use the same `PendingNavigationStore.submit` mechanism via a notification router; the pattern is documented in `/fcm-notifications` but is not wired into the boilerplate
- **Native platform configuration** (`AndroidManifest.xml` intent filters, iOS `Info.plist` + AASA file) — standard `app_links` setup, not project-specific enough for this skill
- **`DeepLinkService.initialize()` ordering in `shared_main.dart`** → `/bootstrap-composition-root` covers the full pipeline ordering

## Reference

See [reference.md](reference.md) for:
- The full `RouteAccessibility` × `AuthShell` dispatch matrix (what happens for every combination)
- URI shape examples: custom-scheme, universal link, with/without query string
- Cold-start dedup edge cases and what `_pendingColdStartDedup` actually catches
- The buffered-broadcast pattern (`_bufferedDispatches`) and why pre-listener events don't drop
- How `_SessionResetBridge` triggers `reset()` and which transitions matter
- Common deeplink-debugging steps (logs, `classifyLocation` testing, simulator commands)

## Checklist

- [ ] Route exists in `AppRoutes` enum with the right path shape (see `/navigation-gorouter`)
- [ ] If the deeplink lands on an authenticated-class target: no extra work — the store buffers until pipeline complete
- [ ] If the deeplink lands on an unauthenticated-class target (login, landing): no extra work — the store dispatches if the current shell allows
- [ ] `EnvConfig.deepLinkHost` and `EnvConfig.customScheme` are set to your associated domain + scheme
- [ ] Native config (Universal Links / Android intent-filter) configured for that host + scheme
- [ ] Tested with `xcrun simctl openurl booted <uri>` / `adb shell am start -d "<uri>"` on cold-start AND warm-start
- [ ] No code outside `DeepLinkService` calls `app_links` directly; no code outside `_AppState` calls `router.go` for external intents
