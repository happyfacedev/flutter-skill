# Auth Flow (Supabase) — Reference

Source files:
- `lib/core/auth/cubit/auth_cubit.dart`
- `lib/core/auth/cubit/auth_state.dart`
- `lib/core/auth/repositories/auth_repository.dart` + `auth_repository_impl.dart`
- `lib/core/auth/models/auth_user.dart`
- `lib/core/services/auth_shell_context.dart`

## `AuthState` shape

```dart
class AuthState extends Equatable {
  final AuthStatus status;        // initial | authenticated | unauthenticated
  final AuthUser? user;            // null when unauthenticated or still initial
  final bool isEmailVerified;      // orthogonal to status — set on auth events

  AuthShell get currentShell;      // derived
  bool get isFullyAuthenticated;   // status == authenticated AND isEmailVerified

  factory AuthState.initial();
  factory AuthState.unauthenticated();

  AuthState copyWith({...});
  Map<String, dynamic> toJson();
  factory AuthState.fromJson(Map<String, dynamic> json);
}
```

### `AuthShell` derivation

| `status` | `isEmailVerified` | → `currentShell` |
|---|---|---|
| `initial` | any | `unauthenticated` |
| `unauthenticated` | any | `unauthenticated` |
| `authenticated` | `false` | `unverified` |
| `authenticated` | `true` | `authenticated` |

`initial` collapses to `unauthenticated` for shell purposes — the router's `redirect` distinguishes "auth check still in flight" vs "actually unauthenticated" via the explicit `status == AuthStatus.initial` check (see `/navigation-gorouter`).

## `AuthRepository` interface

Every method returns the wide `Either<Failure, T>` (typed auth failures as values — never a re-narrowed seam). Implementation in `auth_repository_impl.dart` calls the constructor-injected client (`_client.auth.X(...)` — never `Supabase.instance`) and folds.

### Stream + getters

| Member | Returns | Notes |
|---|---|---|
| `Stream<supabase.AuthState> authStateChanges` | Supabase auth stream | What `AuthCubit` subscribes to |
| `supabase.Session? currentSession` | Current session | For repositories that need the access token |
| `AuthUser? currentUser` | Current user (project-internal type) | What `_checkExistingSession` reads |

### Operations

| Method | Failure cases | Notes |
|---|---|---|
| `signInWithEmail({email, password})` | `InvalidCredentialsFailure`, `EmailNotConfirmedFailure` | Returns `AuthUser` |
| `signUpWithEmail({email, password})` | `EmailAlreadyInUseFailure`, `WeakPasswordFailure` | Returns `AuthUser` |
| `signOut()` | (rare — usually `Unit`) | |
| `checkEmailVerified()` | (refreshes session) | Returns `bool` |
| `resendVerificationEmail(email)` | | `Unit` on success |
| `refreshSession()` | | Returns `AuthUser` |
| `requestPasswordReset(email)` | `PasswordResetFailure` | `Unit` on success |
| `updatePassword(newPassword)` | `WeakPasswordFailure`, `NonceRequiredFailure`, `PasswordUpdateFailure` | `Unit` on success |
| `updateEmail({newEmail})` | `EmailAlreadyInUseFailure`, `InvalidEmailFormatFailure`, `EmailUpdateFailure` | `Unit` on success — Supabase's "Secure email change" sends a confirmation to both old and new addresses |
| `reauthenticateWithPassword({currentPassword})` | `InvalidCurrentPasswordFailure`, `GenericAuthFailure` | Used before sensitive operations |
| `isSocialOnlyAccount()` | (sync) | True when the user has no email identity (social-only account) |
| `currentSocialProvider()` | (sync) | Provider name (`google` / `apple`) or null |

## `AuthShellContext` API

Source: `lib/core/services/auth_shell_context.dart` (read the file for the exact API).

```dart
@singleton
class AuthShellContext {
  // Current shell — read synchronously
  AuthShell? get currentShell;

  // Stream of shell changes — subscribe for reactive consumers
  Stream<AuthShell?> get changes;

  // Called by AuthCubit on every state change
  void publish(AuthState state);
}
```

Consumers:
- **`PendingNavigationStore`** (`@singleton`) — reads `currentShell` synchronously in `submit`, subscribes to `changes` for shell-gated buffering
- **(Future consumers)** — any infra-layer service that needs to react to auth state without importing `AuthCubit`

Producers:
- **`AuthCubit`** — only the cubit publishes to the context. The cubit's constructor publishes the hydrated/initial state immediately; `onChange` republishes on every state change.

## Initialization sequence

`AuthCubit` construction → `@postConstruct` `initialize()`:

```
1. Constructor:
   a. super(AuthState.initial()) — or hydrated state if HydratedCubit found JSON
   b. _authShellContext.publish(state) — publish hydrated/initial state synchronously
   c. (no listener attached yet, no stream events yet)

2. @postConstruct initialize() (awaited by DI's getAsync):
   a. await _checkExistingSession()
      ├── repository.currentUser is non-null → emit(copyWith(authenticated, user, isEmailVerified))
      └── repository.currentUser is null → emit(AuthState.unauthenticated())
      (Either path triggers onChange → publishes to AuthShellContext)

   b. _listenToAuthChanges()
      ├── Cancel any existing subscription
      └── Subscribe to repository.authStateChanges
          └── Map events per the mapping table (see PATTERN.md)
              → emit → onChange → publish

3. App-lifetime: stream events from Supabase drive further emits
```

The order matters: `_checkExistingSession` runs FIRST (step 2a), then the stream listener attaches (step 2b). If the listener attached first, a Supabase `initialSession` event could land mid-check and emit a conflicting state — see PATTERN.md Critical Rule 1.

## `AuthChangeEvent` → `AuthState` mapping (full)

From `_listenToAuthChanges` in `auth_cubit.dart`:

```dart
switch (event) {
  case AuthChangeEvent.signedIn:
  case AuthChangeEvent.tokenRefreshed:
  case AuthChangeEvent.userUpdated:
    if (session?.user != null) {
      final user = AuthUser.fromSupabaseUser(session!.user);
      emit(state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
        isEmailVerified: user.isEmailVerified,
      ));
    }
  case AuthChangeEvent.signedOut:
  case AuthChangeEvent.userDeleted:
    emit(AuthState.unauthenticated());
  case AuthChangeEvent.passwordRecovery:
  case AuthChangeEvent.mfaChallengeVerified:
  case AuthChangeEvent.initialSession:
    // intentional no-op
    break;
}
```

If Supabase adds a new event in a future SDK version, the switch is exhaustive — the compiler flags it.

## HydratedCubit serialization contract

```dart
@override
AuthState? fromJson(Map<String, dynamic> json) {
  try {
    return AuthState.fromJson(json);
  } catch (_) {
    return null;   // HydratedCubit falls back to super(initial)
  }
}

@override
Map<String, dynamic>? toJson(AuthState state) {
  try {
    return state.toJson();
  } catch (_) {
    return null;   // Skip persistence this round
  }
}
```

The try/catch protects against:
- **Schema drift** — a field was renamed or removed; the persisted JSON no longer matches
- **Enum index changes** — `AuthStatus.values[oldIndex]` could throw if the enum was reordered (the current `AuthState.fromJson` already guards index range, but the outer catch is belt-and-suspenders)
- **Corruption** — disk write was interrupted; JSON is malformed

In all three cases the app launches with `AuthStatus.initial`, then `_checkExistingSession` repopulates it correctly via Supabase. Worst-case user impact: one extra splash flash at launch.

## State sequence cheat sheet

### Cold start, no persisted session

```
[init]     status: initial
           |
[ctor]     publish(initial) → AuthShellContext.currentShell = unauthenticated
           |
[ckSession] repository.currentUser == null → emit(unauthenticated)
           |
[stream]   subscribes; no events yet
           |
[user opens app] router reads currentShell=unauthenticated → routes to landing/intro
```

### Cold start, persisted session

```
[init]     status: initial (HydratedCubit found JSON, restored authenticated state with isEmailVerified=true)
           |
[ctor]     publish(authenticated) → AuthShellContext.currentShell = authenticated
           |
[ckSession] repository.currentUser != null → emit(authenticated, user, isEmailVerified) (often a no-op if hydrate matched)
           |
[stream]   subscribes; soon receives `initialSession` event → no-op (already handled)
           |
[user opens app] router reads currentShell=authenticated → routes to startup pipeline
```

### Mid-session sign-in

```
[user submits form] AuthFormCubit.submit() → emits loading
                    repository.signInWithEmail(...) → Supabase RPC
                    |
[Supabase responds] Supabase emits `signedIn` event on authStateChanges
                    |
[stream listener]   emits authenticated + user + isEmailVerified
                    |
[onChange]          publishes to AuthShellContext → triggers PendingNavigationStore re-eval
                    |
[router redirect]   refreshListenable fires → redirect re-evaluates → routes to startup pipeline
                    |
[AuthFormCubit]     submit() future resolves → emits success (cosmetic; page already gone)
```

### Mid-session sign-out

```
[user taps "Sign out"] AuthCubit.signOut() → repository.signOut() → Supabase RPC
                       |
[Supabase responds]    Supabase emits `signedOut` event
                       |
[stream listener]      emits AuthState.unauthenticated()
                       |
[onChange]             publishes to AuthShellContext
                       |
[_SessionResetBridge] listens for shell→unauthenticated → calls:
                       - PendingNavigationStore.reset()
                       - OrganizationContext.clearValidated()
                       - StartupPipelineSessionCache.clear()
                       |
[router redirect]      refreshListenable fires → redirects to landing/intro
```

### Token refresh (silent, background)

```
[Supabase] internal timer fires; refreshes token; emits `tokenRefreshed` event
           |
[stream listener] emits authenticated + (potentially updated) user + isEmailVerified
           |
[onChange] publishes — usually no-op for downstream consumers (shell didn't change)
```

The `tokenRefreshed` case is why `_listenToAuthChanges` re-derives `isEmailVerified` from `session.user.emailConfirmedAt` — if the user verified their email in another device, the refreshed token reflects it and the app updates automatically.

## Common pitfalls

| Pitfall | Symptom | Fix |
|---|---|---|
| Reordered initialize: stream listener before session check | Sporadic "auth state out of sync" — sometimes the user lands on home, sometimes on landing | Restore the order: `await _checkExistingSession();` then `_listenToAuthChanges()` |
| Forgetting to publish in a new state-emitting code path | `PendingNavigationStore` sees stale shell; deeplinks route wrong | Route every emit through `copyWith` + `emit` (which triggers `onChange` → `publish`) — don't bypass `onChange` |
| `fromJson` throws instead of returning null | App fails to start after a schema change | Always wrap in try/catch returning null |
| Loading state added to `AuthState` | Cubit gets bloated, process state mixed with auth state | Loading lives in `AuthFormCubit` or the per-operation cubit, not `AuthCubit` |
| Feature cubit imports `AuthCubit` | Tight coupling, hard to test in isolation | Read via parent-widget `BlocListener` (the bridge pattern) or `AuthShellContext` |
| Subscribing to `authCubit.stream` from another singleton | Tight coupling at the singleton layer, hard to swap | Inject `AuthShellContext` instead — same data, no `AuthCubit` reference |
