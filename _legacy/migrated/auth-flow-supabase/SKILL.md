---
name: auth-flow-supabase
description: The Supabase + HydratedCubit + stream-subscription auth pattern — `AuthCubit` (`@singleton` + `HydratedCubit<AuthState>` + `@postConstruct` initialize) subscribes to `repository.authStateChanges` (Supabase auth stream), maps Supabase events to a project-internal `AuthStatus` + `isEmailVerified`, derives an `AuthShell` getter (`unauthenticated` / `unverified` / `authenticated`), publishes every state change to `AuthShellContext` for infra-layer consumers (`PendingNavigationStore`), and persists via `toJson` / `fromJson` for cross-restart session continuity. Covers the two-step initialization race (`_checkExistingSession` MUST emit before `_listenToAuthChanges` attaches, otherwise a stream event can fire mid-check and emit a conflicting state), the Supabase `AuthChangeEvent` → cubit state mapping table (`signedIn` / `tokenRefreshed` / `userUpdated` → authenticated; `signedOut` / `userDeleted` → unauthenticated; `passwordRecovery` / `mfaChallengeVerified` / `initialSession` → no-op handled by `_checkExistingSession`), the HydratedCubit serialize/deserialize contract (try/catch fallback returning null on bad shape so a schema change doesn't brick the app), the `AuthRepository` Either<AuthFailure, T> contract for imperative operations (sign in / sign up / sign out / password reset / email update / reauthenticate), the social-only-account detection helper, and the `AuthShellContext` bridge that infra services consume so they don't have to know about `AuthCubit`. Use when adding a new auth operation (a new repository method like delete-account or change-2FA), debugging "auth state out of sync" / "splash never clears" / "deeplink ignored on cold start because shell hasn't resolved", changing how a Supabase event maps to internal state, integrating a new infra-layer consumer of auth state, or when the user mentions "AuthCubit", "AuthState", "AuthStatus", "AuthShell", "AuthRepository", "auth state changes", "Supabase auth", "authStateChanges", "HydratedCubit auth", "AuthShellContext", "sign in", "sign out", "token refresh", "session restore", "email verified", or "auth singleton". Form input wiring (email + password validation) → /form-creation. The login/register page wiring → /page-creation. Router's reading of auth state for redirects → /navigation-gorouter. AuthCubit's @singleton registration → /bootstrap-composition-root.
argument-hint: "[auth-operation-or-event]"
---

# Auth Flow (Supabase)

`AuthCubit` is the project's source of truth for "who is signed in and is their email verified." It's an `@singleton` `HydratedCubit` that:

1. **Hydrates** state from local storage at construction (so the first frame after launch already knows the last-known auth status).
2. **Restores** the real session via `_checkExistingSession()` (`@postConstruct`).
3. **Subscribes** to `repository.authStateChanges` (Supabase auth stream) and maps events to internal state.
4. **Publishes** every state change to `AuthShellContext` — an infra-layer broadcast for consumers that can't (or shouldn't) depend on `AuthCubit` directly.

The pattern is deliberately split: `AuthCubit` owns user-facing reactivity (UI rebuilds, router redirect reads); `AuthShellContext` owns infra reactivity (`PendingNavigationStore` reads it without importing the cubit). Both publish the same state — the context is just the cubit's signal repackaged for infra.

This skill is for changing or extending that flow. Most auth-adjacent work is actually form-input work (`/form-creation`) or page work (`/page-creation`); this skill is specifically about touching `AuthCubit`, `AuthState`, `AuthRepository`, or the `AuthShellContext` bridge.

## Critical Rules (Never Break)

1. **`_checkExistingSession` MUST emit before `_listenToAuthChanges` attaches.** *Why:* if the stream listener attaches first and a Supabase stream event (e.g., `initialSession`) lands during the existing-session check, the listener can emit a state that conflicts with what the check is about to emit — and the order is non-deterministic, so the bug only shows up on slow networks. The current `initialize()` awaits the check, then attaches. Don't reorder.

2. **The stream listener handles ONLY the events listed in the mapping table.** *Why:* Supabase's `AuthChangeEvent` enum includes events that aren't actionable here (`passwordRecovery`, `mfaChallengeVerified`, `initialSession`). `initialSession` is explicitly handled by `_checkExistingSession`; emitting again from the stream listener double-counts. The other two have specific flows (password-recovery is handled by the `ForgotPasswordCubit`-driven flow; MFA isn't implemented yet) — letting them through here would emit half-formed state.

3. **`AuthCubit` does NOT manage process state (loading, error).** *Why:* it's a state-based cubit, not a process-status cubit. Process state (sign-in is loading, sign-in failed with InvalidCredentials) lives in `AuthFormCubit` (or the equivalent per-screen cubit) — those are `@injectable` page-scoped cubits that own a single submit operation. The auth-state truth source stays clean: `AuthStatus` is `initial` / `authenticated` / `unauthenticated`, with `isEmailVerified` orthogonal. See `/cubit-creation` for the state-based vs process-status distinction.

4. **NEVER call `AuthCubit` methods from another cubit's constructor or imperative code.** *Why:* the rule is the same as any cubit-to-cubit prohibition (`/cubit-creation` rule 5). Other cubits read auth state via parent-widget `BlocListener` (the `_SessionResetBridge` pattern in `bootstrapper.dart`) or via the read-only `AuthShellContext` service. Importing `AuthCubit` into a sibling feature is a smell.

5. **`fromJson` / `toJson` MUST be defensive — wrap in try/catch and return null on failure.** *Why:* HydratedCubit reads the persisted state at construction. If the JSON shape changed (added a field, renamed an enum value) and `fromJson` throws, the app fails to start — the cubit's persistence layer doesn't catch it. Returning null from `fromJson` makes HydratedCubit fall back to `super(initial)`, which is recoverable: the app launches with `AuthStatus.initial`, then `_checkExistingSession` repopulates it correctly. The current implementation has this safeguard; preserve it.

6. **Every state change publishes to `AuthShellContext`.** *Why:* `PendingNavigationStore` and any other infra consumer reads `AuthShellContext.currentShell` synchronously and subscribes to `.changes`. If a state change skips `_authShellContext.publish(...)`, infra services see stale data and route deeplinks incorrectly. The cubit's `onChange` override publishes on every transition; the constructor publishes the hydrated/initial state immediately. Don't add code paths that emit without publishing.

## The Supabase event mapping

`_listenToAuthChanges` switches on `authState.event` and maps each Supabase event to a `state.copyWith(...)`. The current mapping:

| Supabase `AuthChangeEvent` | Action | Why |
|---|---|---|
| `signedIn` | Emit `authenticated` + `AuthUser.fromSupabaseUser(session.user)` + `isEmailVerified` from user | User just signed in |
| `tokenRefreshed` | Same as `signedIn` | Token rotation produces a fresh session; re-derive `isEmailVerified` in case it changed server-side |
| `userUpdated` | Same as `signedIn` | User changed their email or other profile fields; re-derive `isEmailVerified` |
| `signedOut` | Emit `AuthState.unauthenticated()` | User explicitly signed out |
| `userDeleted` | Emit `AuthState.unauthenticated()` | Account deleted server-side; same effect as sign-out |
| `passwordRecovery` | No-op | Handled by the password-recovery flow (`ForgotPasswordCubit` + dedicated UI), not the auth cubit |
| `mfaChallengeVerified` | No-op | MFA not implemented; would need its own pending-challenge state if added |
| `initialSession` | No-op | Handled by `_checkExistingSession()` — emitting here would double-count |

When adding a new Supabase event (or when Supabase adds one in a future SDK version), decide where it fits:
- **Does it change who's signed in or whether email is verified?** → map it (probably the same shape as `signedIn` or `signedOut`)
- **Is it a transient action (recovery, MFA challenge)?** → no-op in `AuthCubit`, handle in the dedicated cubit
- **Is it `initialSession`-like?** → no-op (the session check owns it)

## Decision: where does this auth-adjacent thing live?

| Concern | Lives in | Why |
|---|---|---|
| "Is the user signed in right now?" | `AuthCubit.state.status == AuthStatus.authenticated` | The truth source |
| "Has the user's email been verified?" | `AuthCubit.state.isEmailVerified` | Same source — read at the same level |
| "Which shell should the router render?" | `AuthCubit.state.currentShell` (derived getter) | Cubit owns the derivation; router reads it |
| "Sign in / out / up imperative call" | `AuthRepository.signInWithEmail(...)` etc. | The repository — returns `Either<AuthFailure, T>` |
| "Sign-in form's loading state" | `AuthFormCubit` (a separate `@injectable` cubit) | Process state belongs in the page-scoped form cubit, not the global auth cubit |
| "Snackbar after sign-in fails" | UI listener on `AuthFormCubit` | Same — page-scoped concern |
| "Redirect on shell transition" | Router's `redirect` callback reading `authCubit.state` | The router owns navigation reactions |
| "Reset deeplink store on logout" | `_SessionResetBridge` listening on `AuthCubit` (parent-widget bridge) | Cubit-to-cubit signalling at the widget layer |
| "Infra service reading shell" | `AuthShellContext.currentShell` (service injection) | Infra services don't import `AuthCubit` directly |

## The two-cubit pattern: `AuthCubit` + `AuthFormCubit`

This is the canonical separation:

- **`AuthCubit`** (singleton, state-based) — owns the *current* auth state. Reacts to external events (Supabase stream). No `loading` or `error` ever.
- **`AuthFormCubit`** (`@injectable`, process-status) — owns the *form being submitted*. Has `BlocStatus.loading` / `success` / `failure`. Calls `AuthRepository.signInWithEmail(...)` and folds the result into local state; the actual session change arrives via `AuthCubit`'s stream listener.

When the user taps "Sign in":
1. `AuthFormCubit.submit()` → emits `loading`
2. `AuthRepository.signInWithEmail(...)` → Supabase RPC
3. On success: Supabase emits `signedIn` event → `AuthCubit` stream listener → emits `authenticated`
4. Router's `refreshListenable` re-fires the redirect → user navigates away from login
5. `AuthFormCubit.submit()` future resolves → emits `success` (mostly cosmetic at this point; the page is already gone)

The two cubits never reference each other. The bridge is the Supabase stream.

## Adding a new auth operation

The shape: a new method on `AuthRepository` (interface + impl), called by a feature-specific cubit (probably `@injectable`).

1. **Add to `AuthRepository`** (`lib/core/auth/repositories/auth_repository.dart`):
   ```dart
   Future<Either<AuthFailure, Unit>> linkPhoneNumber(String phone);
   ```

2. **Implement in `AuthRepositoryImpl`** — call `Supabase.instance.client.auth.X(...)`, fold result into `Either<AuthFailure, T>` per `/network-creation-supabase`.

3. **Add new failure types** (if needed) to `lib/core/auth/failures/auth_failure.dart` per `/failure-modeling`.

4. **Build the feature cubit** that calls this operation (`@injectable` per `/cubit-creation`).

5. **(If the operation produces a Supabase `AuthChangeEvent`)** — confirm the existing event mapping handles it. Most operations (link phone, link OAuth provider, MFA enrollment) emit `userUpdated`, which already maps correctly.

`AuthCubit` itself rarely changes when adding a new operation — the cubit reacts to events; it doesn't initiate them.

## What this skill does NOT cover

- **Sign-in / sign-up / forgot-password form pages** → `/form-creation` (the formz inputs) + `/page-creation` (the page wiring)
- **Auth-related failures** (`InvalidCredentialsFailure`, `EmailNotConfirmedFailure`, `WeakPasswordFailure`) → `/failure-modeling`
- **Router redirect reading auth state** → `/navigation-gorouter` (the redirect priority order)
- **AuthCubit's `@singleton` registration in `Bootstrapper`** → `/bootstrap-composition-root` (the `MultiBlocProvider` slot)
- **Email verification + email-unverified shell UI** → `lib/features/auth/ui/pages/email_unverified_page.dart` and its `EmailVerificationCubit` (specific feature, not a general pattern)
- **Password-recovery flow** → `ForgotPasswordCubit` + dedicated UI; this skill notes that `passwordRecovery` is no-op at the auth-cubit level
- **Social auth (Google / Apple)** — `AuthRepository.isSocialOnlyAccount()` / `currentSocialProvider()` exist; integration with Google/Apple sign-in SDKs is feature work, not in scope here

## Reference

See [reference.md](reference.md) for:
- The full `AuthState` shape with every field's semantics
- The full `AuthRepository` interface (every method's failure list)
- `AuthShell` derivation truth table (status × isEmailVerified → shell)
- `AuthShellContext` API (what it exposes, who reads it)
- Common pitfalls (race in `initialize`, hydration corruption, forgetting to publish to context)
- The full sign-in / sign-up / sign-out / token-refresh state sequences

## Checklist

- [ ] If adding to `AuthRepository`: new method declared on the interface AND implemented on `AuthRepositoryImpl` returning `Either<AuthFailure, T>`
- [ ] If a new failure shape is needed: added to `lib/core/auth/failures/auth_failure.dart` per `/failure-modeling`
- [ ] If the operation produces a new Supabase `AuthChangeEvent`: confirmed the existing mapping in `_listenToAuthChanges` covers it, or added a new case
- [ ] No process state (`loading`, `error`) added to `AuthCubit` / `AuthState` — that's `AuthFormCubit`-shaped
- [ ] No cubit-to-cubit reference to `AuthCubit` from feature cubits — read via parent-widget `BlocListener` or `AuthShellContext`
- [ ] `fromJson` and `toJson` wrapped in try/catch returning null on failure — schema drift must not brick the app
- [ ] State changes flow through `onChange` (which publishes to `AuthShellContext`) — no direct `emit` paths skip the bridge
- [ ] If adding a global infra consumer of auth state: it reads `AuthShellContext`, not `AuthCubit`
- [ ] Tested cold-start hydration: launch with a persisted session, confirm splash → home flow doesn't bounce through landing
- [ ] Tested sign-out: confirm state goes to `unauthenticated` AND `_SessionResetBridge` triggers `PendingNavigationStore.reset()` + related resets
