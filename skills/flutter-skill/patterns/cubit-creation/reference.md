# Cubit Creation Reference

## Decision Trees

### Should this cubit be `@singleton` (app-lifetime) or `@injectable` (page-scoped)?

```
Does this cubit hold state that should survive page navigation?
├─ YES → @singleton + register in Bootstrapper MultiBlocProvider.
│         Common cases: auth session, theme, permissions, language,
│         connectivity, FCM/notifications, force-update gate,
│         intro-seen flag, analytics consent.
└─ NO → Does it own a stream subscription / persistent state / cross-cutting resource?
    ├─ YES → @singleton (same as above — the subscription lifecycle is the reason).
    └─ NO  → @injectable. Fresh instance per BlocProvider(create: ..) on the page.
              Common cases: list pages, detail pages, form cubits.
```

`@singleton` is not just for "auth/theme/permissions" — many legitimate uses exist. The decision is **lifecycle**: does the state or subscription need to outlive a single page visit?

### Which copyWith form does a field get?

```
Is the field a one-shot signal (error) or persistent data?
├─ One-shot (error) → direct assignment: `error: error`.
│    Pass it ONLY on the failure emit. Every other emit clears it
│    automatically — never pass `error: null` explicitly, and never
│    write `error ?? this.error` (it makes failures sticky).
└─ Persistent (status, data, filters, ...) → `field ?? this.field`.
     Pass it only when it changed; omit otherwise.
```

There is no clearing mechanism and none is needed: one-shot fields clear themselves on the next emit, persistent fields are replaced by emitting a new value.

### Standard cubit vs watching cubit?

```
Does this cubit need to react to data it doesn't fetch itself?
├─ YES → Watching cubit. Subscribe in the constructor via the StreamSubscriber
│         mixin (auto-cancels on close). Sources: reactive repository streams
│         (see /reactive-repository), FCM messages, auth state changes,
│         connectivity changes, periodic timers.
└─ NO  → Standard cubit. Methods triggered by UI; one-shot async operations.
```

### Should I check loading state in cubit?

```
YES, by default: `if (state.status == BlocStatus.loading) return;` at the top
of user-action methods — the disabled button is the first defense, the guard
covers the double-tap race before the disabled state propagates.
Skip it deliberately where overlapping calls are legitimate
(e.g. pull-to-refresh restarting a slow load).
```

## Error Handling Pattern

### In Cubit

```dart
result.fold(
  (failure) {
    emit(state.copyWith(status: BlocStatus.failure, error: failure));
    addError(failure, StackTrace.current);   // → AppBlocObserver → snackbar
  },
  (data) => emit(state.copyWith(status: BlocStatus.success, data: data)),
);
```

**Why `emit` AND `addError`?** `emit` updates the UI state (the page can render an error view from `state.error`). `addError` notifies the global `AppBlocObserver`, which routes `Failure` errors to a snackbar. The two surfaces are independent: a feature may use one, the other, or both.

Don't `throw`. Throwing from an unawaited future silently dies — `addError` is the only way to reach the global observer.

Note the success branch does not mention `error` at all — the one-shot copyWith form clears it.

### Failures that should NOT auto-snackbar

Some failures represent business-expected states the UI handles inline (rate limits, validation errors, recoverable conflicts). For these, call `emit` to surface the failure in state but skip `addError` so the global snackbar doesn't double-fire. The failure-modeling pattern covers this in detail.

### Error display in widgets

```dart
// ✅ Correct
if (state.error != null) {
  Column(
    children: [
      Text(state.error!.getTitle(context)),
      if (state.error!.getSubtitle(context).isNotEmpty)
        Text(state.error!.getSubtitle(context)),
    ],
  )
}

// ❌ Wrong — toString() bypasses localization and shows raw class names
Text('Error: ${state.error.toString()}')
```

## HydratedCubit

`HydratedCubit` persists state across app restarts using `hydrated_bloc` storage. It's the standard pattern for any cubit whose state should survive a relaunch — this is the project's persistence mechanism for restart-surviving state (ad-hoc key-value storage via Hive is only for simple values outside cubit state).

Typical uses: theme (dark/light), language, intro-seen flag, analytics consent, auth session (token / current user), permissions snapshot, notification log / preferences. Both UI-state cubits (theme) and feature-state cubits (auth) commonly become `HydratedCubit`s when their state must survive a relaunch.

What NOT to persist: anything cheaper to re-fetch from the network than to keep coherent across launches (lists of records, transient view state). Persisting that creates two sources of truth and stale-cache bugs.

When you do use it:

```dart
@singleton                                // hydrated cubits are usually global
class ThemeCubit extends HydratedCubit<ThemeState> {
  ThemeCubit() : super(const ThemeState());

  @override
  ThemeState fromJson(Map<String, dynamic> json) => ThemeState(
    mode: ThemeMode.values.byName(json['mode'] as String),
  );

  @override
  Map<String, dynamic> toJson(ThemeState state) => {
    'mode': state.mode.name,
  };
}
```

Wiring requirements (must happen before `runApp`):
- `HydratedBloc.storage = await HydratedStorage.build(storageDirectory: ...)`.
- The hydrated cubit must be constructed *after* storage is initialised, otherwise `fromJson` is never called.

If the persisted state is wrong or stale on a future app version, `fromJson` should tolerate it (catch parse errors, fall back to the default) — there is no migration tooling out of the box. The community line matches: fine for UI/preference state, but never the primary store for domain data — re-fetchable records belong to repositories, and a corrupted cache must never be able to lose real data. Note `hydrated_bloc` v10+ stores via `hive_ce` (community fork of the discontinued hive); when upgrading a project across that boundary, verify persisted state survives the storage migration before shipping.

## Passing arguments to the initial load

The default pattern is `..loadData()` with no args. When the first load needs a value (e.g. an id from the route):

**Pattern A — pass via constructor:** the cubit takes the value as a `final` field, `..loadData()` reads it.

```dart
BlocProvider(
  create: (_) => getIt<FeatureCubit>(param1: id)..loadData(),
  ...
)
```

(Requires the DI factory to accept the param — `injectable`'s `@factoryParam` annotation.)

**Pattern B — pass to loadData:** the cubit's loadData takes the arg.

```dart
BlocProvider(
  create: (_) => getIt<FeatureCubit>()..loadData(id: id),
  ...
)
```

Pattern B is simpler when the arg is purely transient (only needed for that one call). Pattern A is right when the cubit needs the arg for multiple methods.

## Inter-Cubit Communication

Cubits are independent. They MUST NOT depend on or call other cubits.

```
Need another cubit to see the result of an action?
├─ Same page: BlocListener on cubit A reads cubit B via context.read
└─ Cross-page / cross-feature: make the shared repository reactive —
   the mutation writes through it; every watching cubit updates
   (see /reactive-repository)
```

```dart
// ❌ Wrong — cubit depending on another cubit
class OrderCubit extends Cubit<OrderState> {
  final CartCubit cartCubit;                  // NEVER inject another cubit
}

// ✅ Correct — parent widget coordinates via BlocListener (same page)
BlocListener<OrderCubit, OrderState>(
  listener: (context, state) {
    if (state.status == BlocStatus.success) {
      context.read<CartCubit>().refresh();
    }
  },
)

// ✅ Correct — write-through a reactive repository (cross-page):
// OrderCubit calls _repo.submitOrder(); on success the repository pushes the
// updated cart into its BehaviorSubject; CartCubit — wherever it lives —
// receives it via its watchCart() subscription. No events, no cubit refs.
```

## Common Mistakes to Avoid

| ❌ Don't | ✅ Do |
|----------|-------|
| `error: error ?? this.error` in copyWith | `error: error` — errors are one-shot, cleared unless passed |
| `emit(state.copyWith(status: ..success, error: null));` | `emit(state.copyWith(status: ..success));` — omitting `error` already clears it |
| Bare `emit` after an `await` | `if (isClosed) return;` first — the page may have been popped mid-request |
| State class without `Equatable`/complete `props` | Extend `Equatable`, list every field — missing props = "UI didn't update" bugs |
| `class MyPage extends StatefulWidget` | `class MyPage extends StatelessWidget` |
| Register page cubits in the global Bootstrapper | Create in `BlocProvider(create: ...)` on the page |
| `context.read<Cubit>()` inside `build` | Use `BlocBuilder` / `BlocSelector` (read is for callbacks only) |
| `Text(error.toString())` | `Text(error.getTitle(context))` |
| Inject a cubit into another cubit | Parent widget `BlocListener` (same page) or a reactive repository stream (cross-page) |
| Per-item flags in the parent list cubit | A small per-item cubit per row |
| Forget to `cancel()` a stream subscription in `close()` | Override `close()`, cancel, then `super.close()` |
| `throw failure;` from inside a cubit method | `emit(...failure state...); addError(failure, StackTrace.current);` |
