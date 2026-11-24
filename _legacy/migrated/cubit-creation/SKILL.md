---
name: cubit-creation
description: Creates Cubit-based business logic for Flutter features — `@injectable` (page-scoped) or `@singleton` (app-lifetime) cubit + manual-`copyWith` state (no Freezed) + `StatelessWidget` page with `BlocProvider`. Covers process-status cubits using `BlocStatus`, streaming cubits that subscribe to `simple_refresh_bus` / FCM / auth-state, and `HydratedCubit` for state that must survive app restarts. Use when adding or modifying any cubit / state / state-aware page, when wiring a feature's business logic to its repository, when integrating cross-cubit signalling via `simple_refresh_bus`, or when the user mentions "cubit", "state", "BlocProvider", "BlocBuilder", "state management", "business logic", or "process status".
argument-hint: "[feature-name]"
---

# Cubit Creation

The standard cubit shape is: `@injectable` (or `@singleton` — see Rule 3) class with constructor-injected repositories → state class with `BlocStatus` enum and manual `copyWith` (no Freezed) → page is `StatelessWidget` with `BlocProvider(create: ..)` that loads on construction. Errors flow via `emit` for UI state and `addError` for the global `AppBlocObserver` snackbar surface.

Failure shapes live in the `failure-modeling` skill; transport (the repository implementations cubits call) lives in `network-creation` / `network-creation-supabase`.

## Critical Rules (Never Break)

1. **NO loading checks on user-action methods.** *Why:* preventing duplicate user actions is a UI concern — buttons disable themselves during loading via `BlocBuilder`. A cubit-level guard silently swallows legitimate re-fires. **Carve-out:** one-time initialization guards (e.g. `if (_initialized) return; _initialized = true;` at the top of an `initialize()` that wires up a long-lived subscription) are fine and necessary — they protect against double-subscription, not against user re-tapping.

2. **NO `StatefulWidget` for cubit pages.** *Why:* `BlocProvider(create: ..)` plus `BlocBuilder` covers everything `initState` / `dispose` would. `StatefulWidget` opens the door to `context.read` in `initState` (which crashes) and parallel lifecycle bugs.

3. **Pick `@injectable` vs `@singleton` deliberately.** Page-local cubits with no cross-page state are `@injectable` (fresh instance per `BlocProvider(create: ..)`). Cubits that hold app-lifetime state, own a stream subscription that must outlive page navigation, or persist via `HydratedCubit` are `@singleton` and registered in the global `Bootstrapper`. *Why:* singletons accumulate state and have wide blast radius; factories drop their state when the page is popped. Examples of legitimate `@singleton` cubit categories: auth, theme, permissions, connectivity, language, notifications, app-version / force-update gate. Real `@injectable` example: per-page list cubits, form cubits, detail-page cubits.

4. **NO `null` in `copyWith` unless explicitly clearing a value.** *Why:* the convention `field ?? this.field` interprets a passed `null` as "keep current value." Passing `null` to mean "actually clear it" requires an explicit Sentinel pattern or `Optional<T>` wrapper — most projects skip that complexity by simply not passing the field when it shouldn't change. If you need true clearing, build a dedicated `clearError()` method that constructs the new state directly.

5. **NO *direct* cubit-to-cubit dependencies.** *Why:* cubits must remain independently testable and replaceable. Injecting `CartCubit` into `OrderCubit` couples their lifecycles and makes both untestable in isolation. Inter-cubit communication routes through one of two patterns: (a) parent widget `BlocListener` coordinates by calling `context.read<OtherCubit>()` in response to state changes, or (b) `simple_refresh_bus` — cubit A fires a typed event, cubit B subscribes (streaming-cubit pattern) and reloads. Indirect signalling via the bus is *not* a dependency — there's no `CartCubit` reference anywhere in `OrderCubit`'s constructor or imports.

## Templates

Replace `Feature` with the actual feature name (`FeatureCubit` → `LoginCubit`, etc.).

- [Standard cubit](templates/cubit.dart) — process-status cubit with injected repository
- [Streaming cubit](templates/streaming_cubit.dart) — cubit that subscribes to a stream (refresh bus, FCM, auth state) in its constructor and cancels in `close()`
- [State](templates/state.dart) — manual state class with `BlocStatus` + `copyWith` (no Freezed)
- [Page](templates/page.dart) — `StatelessWidget` with `BlocProvider`

## Reference

See [reference.md](reference.md) for:
- Decision trees (global vs local cubits, copyWith usage, streaming vs request/response)
- Error display patterns and the `addError` → `AppBlocObserver` flow
- HydratedCubit — when to use it (rarely; only truly cross-session state) and the persistence contract
- Passing arguments to a cubit's initial load when `..loadData()` won't work
- Inter-cubit communication (parent widget vs `simple_refresh_bus`)
- Common mistakes to avoid

→ **Form cubits** (formz inputs + `xxxChanged` + `submit` guarded by `isFormValid`): `/form-creation`.

→ **Auth state cubit** (the canonical `@singleton` + `HydratedCubit` + stream-subscription pattern — Supabase auth events mapped to internal state): `/auth-flow-supabase`.

→ After adding `@injectable` / `@singleton` on a new cubit, rerun `dart run build_runner build --delete-conflicting-outputs`. Full workflow: `/code-generation-workflow`.

## Checklist

- [ ] Cubit class annotated `@injectable` (page-scoped) or `@singleton` (app-lifetime — see Rule 3 decision); dependencies via constructor
- [ ] State class uses `BlocStatus` and manual `copyWith` (no Freezed)
- [ ] **(Streaming cubits)** Subscription created in constructor, cancelled in overridden `close()`
- [ ] Error handling: `emit(state.copyWith(status: BlocStatus.failure, error: failure))` then `addError(failure, StackTrace.current)`
- [ ] No loading checks in cubit methods
- [ ] Page is `StatelessWidget`
- [ ] `BlocProvider(create: (_) => getIt<FeatureCubit>()..loadData())` in the page
- [ ] UI uses a switch expression on `state.status` for the four `BlocStatus` cases
- [ ] Error display uses `failure.getTitle(context)` / `getSubtitle(context)` — never `toString()`
- [ ] `copyWith` calls pass only the fields that changed (no defensive `null`s)