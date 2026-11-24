---
name: navigation-gorouter
description: Works with `lib/core/router/` — `go_router`-based navigation. Covers adding a route to the `AppRoutes` enum + the right accessibility group + a `GoRoute` definition, picking the right page type (`CupertinoPage` / `NoTransitionPage` / `SlideTransitionPage`), the push vs go decision tree, reading typed path/query params + `state.extra`, adding a guard via per-route or global `redirect`, putting a route inside a bottom-nav shell vs full-screen above it (`parentNavigatorKey: rootNavigatorKey`), and the auth-shell-driven redirect priority order (force-update → splash-while-initializing → AuthShell branching). Use when adding any new route, changing a route's accessibility (e.g., moving from authenticated to public), adding navigation guards, debugging "why does it redirect to splash", routing for a deeplink, or when the user mentions "route", "GoRouter", "go_router", "navigate", "AppRoutes", "redirect", "push vs go", "deeplink", "shell route", "bottom nav", "ScaffoldWithNavBar", "pathParameters", "state.extra", "parentNavigatorKey", or "navigation guard". Does NOT cover the deep-link parser itself (separate concern: `DeepLinkService` / `PendingNavigationStore`) or the page widget the route renders → `/page-creation`.
argument-hint: "[route-name]"
---

# Navigation with go_router

`go_router` here is **a redirect-driven state machine over a set of named routes**, not a URL bar. Routes are declared in `AppRoutes` enum + a single `GoRoute` table inside `buildAppRouter(...)`. Navigation decisions are centralized in the `redirect` callback, which reads cubit state synchronously to decide where the user should be. Pages do NOT contain guard logic — they trust the redirect.

The router is a **factory function** (`buildAppRouter`) constructed inside `app.dart`'s widget tree, not a DI singleton. It receives the cubits the redirect reads as constructor parameters, and a `refreshListenable` adapter that re-fires the redirect whenever those cubits emit.

## Critical Rules (Never Break)

1. **All navigation goes through `AppRoutes.<name>.name` / `.path`** — never bare string literals at call sites (`context.pushNamed('/items/123')`). *Why:* the enum is the single source of truth; bare strings drift silently when a path changes, and the grouping lists (`unauthenticatedRoutes`, etc.) only catch enum entries.

2. **Guards belong in the `redirect` callback, not in widgets.** A widget-level guard (`if (!authed) Navigator.of(context).pushReplacementNamed(...)` inside a `BlocListener` or worse, `build`) rebuilds on every state change and fights the router. *Why:* the router's `redirect` runs once per navigation event, reads state synchronously, returns a destination — that's the canonical place. The router's `refreshListenable` re-fires it when cubits emit.

3. **The redirect callback is synchronous — never `await`, never subscribe.** It reads `cubit.state` (current value) and returns a path or `null` immediately. *Why:* the callback sits on the navigation hot path; an async redirect blocks navigation and creates "stuck on splash" bugs. Anything that needs to happen async runs *before* `runApp` (composition root) or in a cubit, not in the redirect.

4. **Use `context.go` to replace the stack, `context.push` to drill in.** Mixing them produces back-stacks that don't match user intent — e.g., `context.push(home)` after sign-in leaves the login screen on the stack, so the back button goes back to login.

5. **Full-screen pages that should cover the bottom nav set `parentNavigatorKey: rootNavigatorKey`.** *Why:* `StatefulShellRoute.indexedStack` keeps the bottom nav present for routes *inside* its branches. Routes that need the bottom nav hidden (detail pages, modals, full-screen forms) must escape via the root navigator. Omitting this on a detail page is the most common "why is the bottom nav still showing?" bug.

## Decision: `context.go` vs `context.push` vs `pushReplacement`

| Situation | Method | Why |
|---|---|---|
| Sign in success, sign out, finishing onboarding | `context.go(path)` | Clears the stack; user should never tap back into the auth flow |
| Bottom-nav tab switch | `context.go(path)` | Tabs are siblings; one tab doesn't sit "on top of" another |
| List → detail (e.g., `ItemsPage` → `ItemDetailPage`) | `context.pushNamed(name, pathParameters: ...)` | User expects back to return to the list |
| Detail action → completion → back to list | `context.pop(result)` from detail | Parent reads the result and refreshes |
| Replace the current page with a sibling (rare — e.g., restart onboarding flow) | `context.pushReplacementNamed(name)` | Keeps the stack but swaps the top entry |
| External redirect → completion page (e.g. a web callback returning to a confirmation page) | `context.go(completionPath)` | Prevents swipe-back into the redirect leg |

**When unclear:** ask. Defaulting to the wrong one creates back-button surprises that are hard to spot in PR review.

## Decision: which page type

Wrap the page widget in the matching `*Page` inside the `pageBuilder` callback:

| Page type | When | Effect |
|---|---|---|
| `CupertinoPage(child: ...)` | Drill-in pages, detail pages, settings sub-pages | iOS-style swipe-back gesture, slide-from-right transition (Material falls back to default Material transition) |
| `NoTransitionPage(child: ...)` | Pre-auth shell routes (intro, landing, login, register, forgot-password), onboarding shell routes, the bottom-nav tabs themselves, force-update | No animated transition — feels like a single state mutation rather than navigation |
| `SlideTransitionPage(child: ...)` | When a custom slide is needed and `CupertinoPage` doesn't fit (rare) | Custom 300ms slide with secondary animation; see `lib/core/router/slide_transition_page.dart` |

A `key: ValueKey(...)` on the page is required when the path can repeat with different params (e.g., navigating from one class detail to another) so the route is rebuilt cleanly.

## Adding a route — the canonical workflow

Step 1. **Add the enum entry** in `lib/core/router/routes.dart`. Pascal-case `name:`, kebab-or-segmented `path:`. Path params use `:paramName`:

```dart
enum AppRoutes {
  // ...existing...
  items('Items', '/items'),
  itemDetail('ItemDetail', '/items/:itemId'),
}
```

Step 2. **Decide the accessibility class.** Add the route to the matching group constant if applicable — `unauthenticatedRoutes`, `unverifiedRoutes`, `publicRoutes`, `onboardingRoutes`. **Authenticated routes do NOT need to be added to any group** — the redirect callback treats "not in any explicit shell group" as authenticated by default. The grouping is purely so the redirect callback knows where unauthed/unverified/etc. users are *allowed* to be.

Step 3. **Add the `GoRoute` definition** in `lib/core/router/router.dart` within the matching section. The file is grouped by accessibility comments (`// Public routes`, `// Unauthenticated routes`, `// Authenticated feature area`, etc.). Insert in the right block. Use `parentNavigatorKey: rootNavigatorKey` for full-screen drill-ins.

Step 4. **Wire `pageBuilder`** with the right page type and any required cubits. Path params are read off `state.pathParameters['name']!` (unwrap with `!` — the path pattern guarantees they exist). Query params live on `state.uri.queryParameters`. Cross-link to `/page-creation` for the page widget itself.

Step 5. **(If guarded)** Either rely on the global redirect (the route lives in / outside the right accessibility group — usually sufficient) OR add a per-route `redirect:` for special cases (e.g. a route that validates a required query/`extra` argument and bounces back if it's missing before rendering).

Step 6. **(If the new route is reachable via deeplink)** Confirm `RouteAccessibility` classification in `lib/core/router/route_accessibility.dart` resolves correctly. Most routes are caught by the segment-matching logic automatically; only add a special case if the route has unusual shape.

→ See [`templates/add_simple_route.dart`](templates/add_simple_route.dart) and [`templates/add_route_with_params.dart`](templates/add_route_with_params.dart) for fill-in scaffolds.

## Reading route arguments

The three argument channels are not interchangeable — pick the right one:

| Channel | Used for | Type-safety | Shareability |
|---|---|---|---|
| **Path params** (`/x/:id`) | Identifying which resource the page is for (`itemId`, `organizationId`) | String only; cast at the page boundary | Encodable in a URL — works for deeplinks |
| **Query params** (`?mode=edit`) | Mode flags, optional config (`ref`, `deadline`) | String only; tolerate missing | Encodable in a URL — works for deeplinks |
| **`state.extra`** | Rich Dart objects the next page needs (`EmailUnverifiedArgs`, a `DateTime` deadline) | Any type | NOT encodable; cold-start deeplinks can't reproduce it — pair it with a query/path param when the page must also be deeplinkable (the dual-channel pattern) |

**Rule of thumb:** if a deeplink should be able to land on the page, the data must live in path or query params. `state.extra` is for in-app navigation only.

## The redirect priority order

`_handleRedirect` in `router.dart` runs in this fixed order — each step short-circuits if it matches:

1. **Force-update check not complete yet** → stay on splash.
2. **Force-update required** → force-update page.
3. **Auth status `initial`** (session restore in flight) → stay on splash.
4. **`AuthShell.unauthenticated`** → if not on an allowed unauth route (`unauthenticatedRoutes` + `/email-unverified` carve-out), redirect to landing or intro depending on `introSeenState`.
5. **`AuthShell.unverified`** → if not on `/email-unverified`, redirect there.
6. **`AuthShell.authenticated`** → if on an auth route, redirect to startup pipeline; otherwise allow.

Adding a new gate (e.g., a "must accept new ToS" interstitial) means picking the right insertion point in this order — usually between force-update and auth-status, or after the auth-shell switch. *Don't* re-implement the gate in a widget; insert it here.

## Routes inside the bottom-nav shell vs above it

The boilerplate ships with a single authenticated route (`home`) and no bottom-nav shell yet — `router.dart` notes where a `ScaffoldWithNavBar` would go if you add tabs. When you do add a bottom-nav shell, the pattern is: tabs live inside a `StatefulShellRoute.indexedStack`. Routes **inside** the shell's `StatefulShellBranch.routes` keep the bottom nav visible — these are tab-rooted routes only. Routes that should drill in full-screen (cover the bottom nav) are declared **outside** the shell and set `parentNavigatorKey: rootNavigatorKey`.

```
StatefulShellRoute.indexedStack    ← keeps the bottom nav
├── branch: Home → /
├── branch: Items → /items
├── branch: Activity → /activity
└── branch: More → /more

Routes outside the shell, with parentNavigatorKey: rootNavigatorKey   ← full-screen, bottom nav hidden
├── /items/:itemId             (item detail)
├── /settings/*                (settings sub-pages)
└── ...
```

If you add a detail-style route inside a `StatefulShellBranch.routes` list, it will render *inside* the tab — the bottom nav stays visible. That's almost never what you want for a detail page.

## Per-route scoped cubits

Two patterns appear inside `pageBuilder`:

**Fresh-per-entry cubit** — wraps the page in a `BlocProvider(create: ...)` for cubits that should not persist across navigations:

```dart
GoRoute(
  name: AppRoutes.termsAcceptance.name,
  path: AppRoutes.termsAcceptance.path,
  pageBuilder: (context, state) => NoTransitionPage(
    child: BlocProvider(
      create: (_) => getIt<TermsCubit>()..checkTermsStatus(),
      child: const TermsAcceptancePage(),
    ),
  ),
),
```

**Shared cubit across sibling pages** — uses `BlocProvider.value` for a cubit constructed elsewhere (the `ProfileCubit` lives at the shell level and is reused in `SettingsProfilePage`, `PersonalInfoPage`, etc.):

```dart
pageBuilder: (context, state) => CupertinoPage(
  child: BlocProvider.value(
    value: getIt<ProfileCubit>(),
    child: const PersonalInfoPage(),
  ),
),
```

`BlocProvider.value` inside `pageBuilder` is one of the carve-outs to the "no `.value` outside tests" rule (see `/bootstrap-composition-root`) — the router is part of the composition root. The standard `BlocProvider(create: ...)` carve-out from `/cubit-creation` still applies when the cubit is page-scoped.

## What this skill does NOT cover

- **The page widget itself** (Scaffold, BlocBuilder, Semantics, theme tokens) → `/page-creation`
- **The cubit the page constructs** → `/cubit-creation`
- **Parsing a `boilerplate://` URI into a `NavigationIntent`, the cold-start + warm-start pipeline, `PendingNavigationStore` buffering** → `/deep-link-handling`
- **Bridging external triggers (e.g. push taps, when added) to navigation** → `/fcm-notifications` (pattern only — not wired into the boilerplate)
- **The composition-root pieces** the router reads (which cubits are global, where they're initialized) → `/bootstrap-composition-root`

## Templates

- [`templates/add_simple_route.dart`](templates/add_simple_route.dart) — straightforward `CupertinoPage` route added inside or outside the shell
- [`templates/add_route_with_params.dart`](templates/add_route_with_params.dart) — path params + query params + `state.extra` + per-route redirect

## Reference

See [reference.md](reference.md) for:
- The full `AppRoutes` accessibility-grouping rules
- The `RouteAccessibility` enum and how it interacts with `PendingNavigationStore`
- Page-type choice table with concrete examples
- The redirect priority order with the file location of each step
- Common navigation patterns by source (from list, from button, from snackbar action, from notification tap)

## Checklist

- [ ] Enum entry added to `AppRoutes` in `routes.dart`, with kebab-or-segmented `path` and Pascal-case `name`
- [ ] If unauthenticated / unverified / public / onboarding, added to the matching `*Routes` constant
- [ ] `GoRoute` entry added in `router.dart` in the right comment section (Public / Unauthenticated / Onboarding / Authenticated / etc.)
- [ ] Page type picked deliberately: `CupertinoPage` (drill-in), `NoTransitionPage` (shell), `SlideTransitionPage` (custom)
- [ ] `parentNavigatorKey: rootNavigatorKey` set if the route should hide the bottom nav
- [ ] Path params read via `state.pathParameters['name']!`, query via `state.uri.queryParameters`, rich objects via `state.extra` — appropriate channel chosen
- [ ] Cubits scoped via `BlocProvider(create:)` for fresh-per-entry or `BlocProvider.value` for shared
- [ ] `key: ValueKey(...)` on the page if the same path can be navigated to with different params
- [ ] Navigation method (`go` vs `push`) chosen per the decision table — and double-checked with user when unclear
- [ ] If guarded by special logic (not just which accessibility group it's in), a per-route `redirect:` is wired
- [ ] Page widget itself follows `/page-creation` (Scaffold + SafeArea + BlocBuilder with buildWhen + Semantics)
