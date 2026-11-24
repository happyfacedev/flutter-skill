# Navigation — Reference

Source files: `lib/core/router/routes.dart`, `lib/core/router/router.dart`, `lib/core/router/slide_transition_page.dart`, `lib/core/router/route_accessibility.dart`. Authoritative on current routes; this page is the lookup index.

## `AppRoutes` accessibility groups

| Group | Constant in `routes.dart` | Meaning | Examples |
|---|---|---|---|
| **Public** | `publicRoutes` | Always allowed regardless of auth state | `splash`, `verificationComplete`, `forceUpdate`, `offline` |
| **Unauthenticated** | `unauthenticatedRoutes` | Allowed only when logged out | `introCarousel`, `landing`, `authOptions`, `login`, `register`, `forgotPassword` |
| **Unverified** | `unverifiedRoutes` | Allowed only when email not yet confirmed | `emailUnverified` |
| **Onboarding** | `onboardingRoutes` | Allowed only inside the authenticated startup pipeline | `startupPipeline`, `organizationResolution`, `organizationSelector`, `termsAcceptance` |
| **Authenticated** *(implicit)* | Not in any group | Allowed only after pipeline completes | `home` (plus any feature routes you add — items, settings, etc.) |

A route NOT in any group is treated as authenticated by default. To make a new route reachable when logged out, ALSO add it to `unauthenticatedRoutes`.

## `RouteAccessibility` enum

Lives in `route_accessibility.dart`. The `classifyLocation(path)` function maps a URL path to one of these classes for `PendingNavigationStore` to decide buffering behavior:

| Value | When | Pending-store behavior |
|---|---|---|
| `publicAlways` | Path matches `publicRoutes` | Drop — never a valid deeplink target |
| `unauthenticated` | Path matches `unauthenticatedRoutes` | Dispatch only when not authenticated |
| `unverified` | Path matches `unverifiedRoutes` | Dispatch only when in unverified shell |
| `onboarding` | Path matches `onboardingRoutes` | Drop — pipeline cubit owns navigation to these |
| `authenticated` | Path matches a declared `AppRoutes` entry not in any of the above | Buffer until pipeline completes; then dispatch |
| `unknown` | Path doesn't match any `AppRoutes.path` pattern | Route to `errorBuilder` → `RouteNotFoundPage` |

When adding a route the matching system catches it automatically via the segment-shape matcher in `_matchesPattern`. Only edit `route_accessibility.dart` if the route has an unusual path shape that the matcher can't handle.

## Page type choice — concrete cases

| Page type | Used by these routes | Reasoning |
|---|---|---|
| `CupertinoPage` | Auth pages (`login`, `register`, `forgotPassword`, `emailUnverified`, `authOptions`), `organizationSelector`, dev `permissionsTest`, and any drill-in detail / settings pages you add | Drill-in pages — iOS swipe-back, slide-from-right; Material falls back to platform default |
| `NoTransitionPage` | `forceUpdate`, `introCarousel`, `landing`, `offline`, `startupPipeline`, all `onboardingRoutes`, `home` (and any bottom-nav tab routes you add) | Shell pages — switching feels like a state mutation, not navigation |
| `SlideTransitionPage` | Available for when a custom horizontal slide is wanted and `CupertinoPage` doesn't fit | Custom 300ms slide; see `slide_transition_page.dart` |

## Redirect priority order

`_handleRedirect()` in `router.dart` runs in this fixed order — each step short-circuits if it matches:

1. **Force-update check not complete yet** → stay on splash.
2. **Force-update required** → force-update page.
3. **On the force-update page but no update required** → splash.
4. **`authState.status == AuthStatus.initial`** (session restore in flight) → stay on splash.
5. **On `verificationComplete`** → allowed always.
6. **`AuthShell.unauthenticated`** → landing or intro (depending on `introSeenState`).
7. **`AuthShell.unverified`** → `emailUnverified`.
8. **`AuthShell.authenticated`** → startup pipeline if on an auth route, otherwise allow.

Steps 1–4 are "stay on splash / force-update while X is loading" gates. Steps 6–8 are the actual shell branching. Insert new gates **before** step 6, after step 4 — that's the "post-auth, pre-shell" slot.

## Cross-scheme deeplink preprocessor

`handleRedirect` in `router.dart` runs this BEFORE calling `_handleRedirect`:

- If `state.uri.scheme` is non-empty and not `http`/`https` (i.e., `boilerplate://`), reconstruct the path from `uri.host` + `uri.pathSegments`
- Preserve query string + fragment so route handlers reading `state.uri.queryParameters` still see deeplink params
- Reroute to the reconstructed path **only if the current auth shell can reach it** (matches `PendingNavigationStore.submit`'s reachability rule)
- Otherwise fall through — navigation proceeds to `/` and `_handleRedirect` resolves correctly per shell

This is the **only** routing-layer code that understands `boilerplate://` URIs. The deeplink parser elsewhere (`DeepLinkService` / `DeepLinkParser`) builds `NavigationIntent`s; this preprocessor handles the case where `app_links` delivers the URI directly to GoRouter before our parser has a chance.

## Common navigation patterns by source

| From | Method | Example |
|---|---|---|
| List card tap → detail | `context.pushNamed(name, pathParameters: {...})` | `context.pushNamed(AppRoutes.itemDetail.name, pathParameters: {'itemId': item.id})` |
| Tab switch from custom action | `context.goNamed(name)` | `context.goNamed(AppRoutes.home.name)` |
| Sign-in success | `context.go(AppRoutes.startupPipeline.path)` from an auth cubit listener at the page level | Stack cleared so back doesn't return to login |
| Sign-out from settings | `context.go(AppRoutes.landing.path)` from a listener after `AuthCubit` emits `unauthenticated` | The router redirect would do this anyway; explicit go avoids one redirect bounce |
| Back from detail with result | `context.pop(result)` | Parent reads result and acts |
| External redirect → completion page | `context.go(...completion path...)` | `pushReplacement` would also work; `go` is preferred so back-button on the completion page returns to the list, not the redirect leg |
| Deep link (cold start) | Captured into `PendingNavigationStore` by `DeepLinkService`; dispatched once pipeline completes | Not via `context.*` directly |
| Snackbar action button | `ScaffoldMessenger.of(context).showSnackBar(... action: SnackBarAction(onPressed: () => context.pushNamed(...)))` | Same as any other in-app navigation |

## `GoRouterRefreshStream` — re-firing the redirect

The `refreshListenable` parameter of `GoRouter` is what re-runs `redirect` when something the redirect *reads* changes. Otherwise the redirect runs only on explicit navigation, which means a cubit emit (e.g., auth state changing from `initial` to `authenticated`) wouldn't trigger a redirect off the splash screen.

`buildAppRouter` wires this from cubit streams via `GoRouterRefreshStream`. Adding a new cubit to the redirect means adding its `.stream` to the listenable list at the caller in `app.dart`.
