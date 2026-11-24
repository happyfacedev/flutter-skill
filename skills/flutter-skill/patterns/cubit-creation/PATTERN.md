# Cubit Creation

The standard cubit shape: `@injectable` (or `@singleton` — see Rule 3) class with constructor-injected repositories → state class with the project's shared `BlocStatus` enum (import it from `lib/core/utils/` — never redefine a local copy, which forks the UI's status switches) and manual `copyWith` (no Freezed) → page is `StatelessWidget` with `BlocProvider(create: (_) => getIt<X>()..loadData())`. Errors flow via `emit` for UI state and `addError` for the global `AppBlocObserver` snackbar surface.

Failure shapes belong to the failure-modeling pattern; transport (the repositories cubits call) belongs to the network patterns.

## Critical Rules (Never Break)

1. **Guard user-action methods against double-fire:** `if (state.status == BlocStatus.loading) return;` at the top of action methods. *Why:* the UI's disabled button is the first line of defense, but a fast double-tap can fire before the disabled state propagates — the guard makes the cubit safe regardless of UI discipline. **Deliberately skip it** when overlapping calls are legitimate (e.g. pull-to-refresh restarting a slow load) — that's a per-method decision. One-time initialization guards (`if (_initialized) return;`) for subscription wiring remain standard.

2. **NO `StatefulWidget` for cubit pages.** *Why:* `BlocProvider(create: ..)` plus `BlocBuilder` covers everything `initState`/`dispose` would, and `StatefulWidget` opens the door to `context.read` in `initState` (which crashes) and parallel lifecycle bugs.

3. **Pick `@injectable` vs `@singleton` deliberately.** Page-local cubits with no cross-page state are `@injectable` (fresh instance per `BlocProvider(create: ..)`). Cubits that hold app-lifetime state, own a stream subscription that must outlive page navigation, or persist via `HydratedCubit` are `@singleton`, registered in the global `Bootstrapper`. *Why:* singletons accumulate state and have wide blast radius; factories drop their state when the page is popped. Legitimate `@singleton` categories: auth, theme, permissions, connectivity, language, notifications, force-update gate. Typical `@injectable`: list, detail, and form cubits. A new `@singleton` needs explicit user approval (router core rule) — record it with an `// Approved as @singleton: <one-line why>` comment on the class so the approval survives review; working headless with no way to ask, default to `@injectable` and flag the singleton candidate instead.

4. **One-shot fields — `error`, `failure`, or any field holding a transient `Failure` — are assigned directly in `copyWith`, never `field ?? this.field`.** Persistent fields use `field ?? this.field`; the one-shot field uses plain direct assignment (`error: error`), so every emit that doesn't pass it clears it. This applies whatever the field is named. *Why:* errors are single-use signals. With `?? this.error` a failure sticks in state forever — a later success emit still carries the stale error and the UI re-renders it. Direct assignment makes loading/success emits clear old errors automatically; no `clearError()` methods, no sentinel parameters, and never pass an explicit `null` for it (omitting it already clears).

5. **NO direct cubit-to-cubit dependencies.** *Why:* cubits must stay independently testable and replaceable; injecting `CartCubit` into `OrderCubit` couples their lifecycles. Coordinate via (a) a parent widget `BlocListener` calling `context.read<OtherCubit>()` for same-page coordination, or (b) a **reactive repository stream** — the mutation writes through the shared repository, which pushes the fresh value to every watching cubit (see `/reactive-repository`). Watching a repository is not a dependency: no cubit reference crosses the boundary.

   **Don't dodge this rule by merging the two cubits into one.** When a mutation's result must update state another cubit owns, make the shared repository reactive and write through it. Folding the mutation into the shared display cubit instead leaks the mutation's `loading`/`failure` lifecycle into every widget watching the display state (a save spinner flashing on screens that only render the data).

6. **`if (isClosed) return;` after every `await`, before any `emit`.** *Why:* the user can navigate away while a request is in flight — `BlocProvider` closes the cubit, the response lands, and `emit` throws `StateError: Cannot emit new states after calling close`. A real crash class on fast navigation; the guard is one line.

7. **State classes extend `Equatable`, with every field in `props`.** *Why:* bloc skips emitting states equal to the current one — a missing field in `props` is the classic "I emitted but the UI didn't update" bug; equality also powers `buildWhen` narrowing and test assertions.

8. **Per-item state gets per-item cubits.** List items with individual loading/action states each get their own small cubit — never a map of per-item flags inside the parent cubit. *Why:* parent-managed per-item state rebuilds the whole list on every item change and turns the parent state into a synchronization problem.

## Templates

Replace `Feature` with the actual feature name (`FeatureCubit` → `LoginCubit`) and `your_app` with the project's package name.

- [Standard cubit](templates/cubit.dart) — process-status cubit with injected repository
- [State](templates/state.dart) — `Equatable` state class with `BlocStatus` + manual `copyWith` (persistent vs one-shot fields)
- [Page](templates/page.dart) — `StatelessWidget` with `BlocProvider`

Cubits that watch a shared repository stream (cross-page data, badges, late subscribers) → `/reactive-repository` (watching-cubit + `StreamSubscriber` mixin templates live there). Non-repository streams (FCM, auth state, connectivity) use the same `StreamSubscriber` mixin.

## Reference

See [reference.md](reference.md) for:
- Decision trees (`@singleton` vs `@injectable`, copyWith field forms, streaming vs request/response)
- Error handling: `emit` + `addError` → `AppBlocObserver`, the no-auto-snackbar carve-out, error display via `getTitle`/`getSubtitle`
- HydratedCubit — when to use it and the persistence contract (this is the project's persistence mechanism for restart-surviving state)
- Passing arguments to the initial load
- Inter-cubit communication examples
- Common mistakes table

→ After adding `@injectable`/`@singleton` on a new cubit, rerun `dart run build_runner build --delete-conflicting-outputs`.

## Checklist

- [ ] Cubit annotated `@injectable` (page-scoped) or `@singleton` (app-lifetime — Rule 3); dependencies via constructor
- [ ] State class uses the shared `BlocStatus` (imported, never a local redefinition) and manual `copyWith` (no Freezed)
- [ ] `copyWith`: persistent fields `field ?? this.field`; the one-shot error/failure field assigned directly (`error: error`) — never `?? this.<field>`, never explicit `null`
- [ ] Error path: `emit(state.copyWith(status: BlocStatus.failure, error: failure))` then `addError(failure, StackTrace.current)`
- [ ] Loading guard (`if (state.status == BlocStatus.loading) return;`) on user-action methods with double-fire exposure (Rule 1); deliberately skipped only where overlapping calls are legitimate
- [ ] Page is `StatelessWidget` with `BlocProvider(create: (_) => getIt<FeatureCubit>()..loadData())`
- [ ] UI switches on `state.status` for the four `BlocStatus` cases
- [ ] Error display uses `failure.getTitle(context)` / `getSubtitle(context)` — never `toString()`
- [ ] **(Watching)** repository-stream subscriptions created in the constructor via the `StreamSubscriber` mixin (auto-cancels on close) — see `/reactive-repository`
- [ ] `if (isClosed) return;` after every `await` before `emit`
- [ ] State extends `Equatable` with every field in `props`
- [ ] `copyWith` calls pass only fields that changed; `error` passed only on the failure emit
