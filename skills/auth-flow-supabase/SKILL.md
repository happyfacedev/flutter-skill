---
name: auth-flow-supabase
description: Internal flutter-skill pattern — invoked via the flutter-skill router, not from this description. (Supabase auth flow.)
---

# Auth Flow (Supabase)

`AuthCubit` is the project's source of truth for "who is signed in and is their email verified." It's a `@singleton` `HydratedCubit` that (1) **hydrates** the last-known state at construction so the first frame already knows, (2) **restores** the real session in `initialize()` (`@postConstruct`), (3) **subscribes** to `repository.authStateChanges` and maps Supabase events to internal state, and (4) **publishes** every change to `AuthShellContext` — the read-only bridge infra services consume so they never import the cubit.

The split is deliberate: `AuthCubit` owns user-facing reactivity (UI rebuilds, router redirect reads); `AuthShellContext` owns infra reactivity (deep-link stores, startup steps). This skill is for touching `AuthCubit`, `AuthState`, `AuthRepository`, or that bridge. Most auth-adjacent work is actually form work (`/form-creation`) or page work (`/ui`) — check the decision table before editing the flow.

## Critical rules

1. **`initialize()` awaits `_checkExistingSession()` BEFORE attaching the stream listener.** *Why:* if the listener attaches first, a stream event (e.g. `initialSession`) can land mid-check and emit a state the check then contradicts — non-deterministically, so it only reproduces on slow networks. Don't reorder.

2. **The restored session is unvalidated — trusting it is safe only because the stream corrects it.** `Supabase.initialize()` restores the persisted session without server-side validation; `_checkExistingSession` optimistically emits `authenticated` from it. That's sound *only* while the stream subscription exists: a revoked/expired refresh token surfaces as `signedOut` on the first refresh attempt, which the mapping turns into a hard sign-out. *Why this framing matters:* never gate startup solely on `currentSession != null` without the subscription, and never catch a refresh-token failure and retry it — a used refresh token is permanently burned; the only correct response is the sign-out path the mapping already provides.

3. **The stream listener handles ONLY the events in the mapping table below.** *Why:* `initialSession` is owned by `_checkExistingSession` (emitting again double-counts); `passwordRecovery` belongs to the recovery flow's own cubit; `mfaChallengeVerified` needs its own pending-challenge state if MFA ever lands. Letting them through emits half-formed state.

4. **`AuthCubit` holds NO process state — no `loading`, no `error`, ever.** *Why:* it's a state-based truth source, not a process cubit. Submission lifecycles (sign-in loading, invalid-credentials error) live in page-scoped `@injectable` cubits (`AuthFormCubit` etc.). Mixing them makes every auth-state consumer rebuild on one page's spinner.

5. **No feature cubit calls `AuthCubit` — coordinate via a parent-widget `BlocListener` or read `AuthShellContext`.** *Why:* cubit-creation Rule 5; auth is the most-tempting cubit to couple to, and the bridge exists precisely so nothing has to.

6. **`fromJson`/`toJson` are defensive — try/catch returning `null`.** *Why:* HydratedCubit deserializes at construction; a schema change that throws bricks app startup. Returning `null` falls back to `AuthStatus.initial`, and `_checkExistingSession` repopulates — recoverable by design.

7. **Every state change publishes to `AuthShellContext` — the `onChange` override, no bypass emits.** *Why:* infra consumers read `currentShell` synchronously; one unpublished transition and cold-start deep links route against stale auth state.

8. **Repository operations return the wide seam `Either<Failure, T>` (typed auth failures flow as values; never re-narrow to `Either<AuthFailure, T>` — network-creation-supabase Rule 7 applies to auth like any transport) with the `SupabaseClient` constructor-injected — never `Supabase.instance` inside methods.** **Deep-link auth flows (email confirmation, magic links, password recovery) require `AuthFlowType.pkce` at `Supabase.initialize`.** *Why:* the implicit flow races the cold-start deep link handler for the URL fragment; PKCE exchanges a code instead, which survives the race.

## The Supabase event mapping

`_listenToAuthChanges` switches on `authState.event`:

| `AuthChangeEvent` | Action |
|---|---|
| `signedIn`, `tokenRefreshed`, `userUpdated` | Emit `authenticated` + `AuthUser.fromSupabaseUser(session.user)` + re-derived `isEmailVerified` (refresh/update can change it server-side) |
| `signedOut`, `userDeleted` | Emit `AuthState.unauthenticated()` |
| `passwordRecovery`, `mfaChallengeVerified`, `initialSession` | No-op (owned elsewhere — Rule 3) |

Adding a new event (or a future SDK adds one): changes who's signed in / email verification → map it like `signedIn`/`signedOut`; transient action → no-op here, dedicated cubit owns it; `initialSession`-like → no-op.

## The two-cubit pattern

- **`AuthCubit`** (singleton, state-based) — current auth truth; reacts to the stream.
- **`AuthFormCubit`** (`@injectable`, process-status) — owns one submission; `loading`/`success`/`failure`; calls `AuthRepository`.

Sign-in: form cubit emits `loading` → repository call → Supabase emits `signedIn` → `AuthCubit` emits `authenticated` → router's `refreshListenable` redirects → form cubit's `success` lands on an already-gone page. The two cubits never reference each other — the Supabase stream is the bridge.

## Where does this auth-adjacent thing live?

| Concern | Lives in |
|---|---|
| "Is the user signed in?" / "email verified?" | `AuthCubit.state` (`status`, `isEmailVerified`) |
| Which shell the router renders | `AuthCubit.state.currentShell` (derived getter) |
| Sign in/out/up, password reset, reauthenticate | `AuthRepository` → wide `Either<Failure, T>` |
| A form's loading/error during submit | The page-scoped form cubit (`/form-creation`) |
| Redirect on shell transition | Router `redirect` reading auth state (`/navigation-gorouter`) |
| Infra service needing auth state | `AuthShellContext` — never the cubit |
| Cleanup on sign-out (stores, caches) | A parent-widget bridge listening on `AuthCubit` (e.g. `_SessionResetBridge` in the bootstrapper) |

## Adding a new auth operation

1. Declare on `AuthRepository`, implement in `AuthRepositoryImpl` per `/network-creation-supabase` (injected client, wide seam). **If the existing interface methods are narrow `Either<AuthFailure, T>`, that's pre-port legacy — your NEW method is still wide `Either<Failure, T>`, with no `_toAuthFailure(...)` re-narrowing fold.** The mixed file is the intended intermediate state (skill-precedence); copying the neighbors re-labels offline as an auth error and kills the app-wide "no connection" message.
2. New failure subtypes → `lib/core/auth/failures/` per `/failure-modeling`.
3. Build the calling `@injectable` cubit per `/cubit-creation`.
4. If the operation produces an `AuthChangeEvent`, confirm the mapping covers it — most (link provider, update email, MFA enroll) emit `userUpdated`, already mapped. `AuthCubit` itself rarely changes: it reacts to events, it doesn't initiate them.

## Not covered here

Sign-in/sign-up/recovery **pages** → `/ui` + `/form-creation`; auth failure shapes → `/failure-modeling`; redirect priority → `/navigation-gorouter`; the cubit's `Bootstrapper` registration → the composition-root pattern (migrating); social-provider SDK integration → feature work.

## Reference

[reference.md](reference.md): full `AuthState`/`AuthRepository`/`AuthShellContext` surfaces, the shell-derivation truth table, initialization sequence, per-scenario state sequences (cold start ± session, sign-in/out, token refresh), pitfalls.

## Checklist

- [ ] New repository method on interface AND impl, wide `Either<Failure, T>` seam, injected client
- [ ] New failures per `/failure-modeling` (const, ARB keys in the same change)
- [ ] Event mapping covers any `AuthChangeEvent` the operation produces
- [ ] No process state added to `AuthCubit`/`AuthState`
- [ ] No feature-cubit reference to `AuthCubit` — widget bridge or `AuthShellContext`
- [ ] `fromJson`/`toJson` still defensive (try/catch → null)
- [ ] All emits flow through `onChange`'s publish — no bridge bypass
- [ ] Deep-link auth flows: PKCE confirmed at `Supabase.initialize`
- [ ] Cold-start check: persisted session → splash → home without bouncing through landing; sign-out triggers the reset bridge
