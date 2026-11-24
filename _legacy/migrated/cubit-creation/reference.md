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

### What to include in copyWith?

```
Has this field changed?
├─ YES → Pass the new value
└─ NO → Is this explicitly clearing the value?
    ├─ YES → Pass null (and accept the `?? this.field` will keep the old value
    │         — for true clearing, use a Sentinel pattern or just don't use copyWith)
    └─ NO → Omit from copyWith
```

### Standard cubit vs streaming cubit?

```
Does this cubit need to react to events it doesn't trigger itself?
├─ YES → Streaming cubit. Subscribe in constructor, cancel in close().
│         Examples: simple_refresh_bus events (RefreshBusSubscriber mixin),
│         FCM messages, auth state changes,
│         connectivity changes, periodic timers.
└─ NO  → Standard cubit. Methods triggered by UI; one-shot async operations.
```

### Should I check loading state in cubit?

```
NO. Never. UI prevents duplicate actions by disabling the button via BlocBuilder.
A cubit-level guard duplicates that logic and silently swallows legitimate
re-fires (e.g. a user pulling-to-refresh while the first load is still in flight).
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

### Failures that should NOT auto-snackbar

Some failures represent business-expected states the UI handles inline (rate limits, validation errors, recoverable conflicts). For these, call `emit` to surface the failure in state but skip `addError` so the global snackbar doesn't double-fire. The failure-modeling skill covers this in detail.

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

`HydratedCubit` persists state across app restarts using `hydrated_bloc` storage. It's the standard pattern for any cubit whose state should survive a relaunch.

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

If the persisted state is wrong or stale on a future app version, `fromJson` should tolerate it (catch parse errors, fall back to the default) — there is no migration tooling out of the box.

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
Need to trigger another cubit after an action?
├─ Parent widget layer: BlocListener on cubit A reads cubit B via context.read
└─ simple_refresh_bus: Cubit A sends a refresh event, cubit B listens (streaming variant)
```

```dart
// ❌ Wrong — cubit depending on another cubit
class OrderCubit extends Cubit<OrderState> {
  final CartCubit cartCubit;                  // NEVER inject another cubit
}

// ✅ Correct — parent widget coordinates via BlocListener
BlocListener<OrderCubit, OrderState>(
  listener: (context, state) {
    if (state.status == BlocStatus.success) {
      context.read<CartCubit>().refresh();
    }
  },
)

// ✅ Correct — fire-and-forget via simple_refresh_bus package (use the
// RefreshBusSubscriber mixin on the receiving end — see streaming_cubit.dart)
class OrderCubit extends Cubit<OrderState> {
  OrderCubit(this._repo) : super(const OrderState());
  final OrderRepository _repo;

  Future<void> submit() async {
    final result = await _repo.submit();
    result.fold(
      (failure) { /* ... */ },
      (_) {
        emit(state.copyWith(status: BlocStatus.success));
        // CartCubit subscribes via `onData<OrderSubmitted>(...)`
        RefreshBus.instance.push<OrderSubmitted>(const OrderSubmitted());
      },
    );
  }
}
```

## Common Mistakes to Avoid

| ❌ Don't | ✅ Do |
|----------|-------|
| `if (state.status == BlocStatus.loading) return;` | Let UI disable buttons during loading |
| `emit(state.copyWith(status: ..success, error: null));` | `emit(state.copyWith(status: ..success));` (omit unchanged) |
| `class MyPage extends StatefulWidget` | `class MyPage extends StatelessWidget` |
| Register page cubits in the global Bootstrapper | Create in `BlocProvider(create: ...)` on the page |
| `context.read<Cubit>()` inside `build` | Use `BlocBuilder` / `BlocSelector` (read is for callbacks only) |
| `Text(error.toString())` | `Text(error.getTitle(context))` |
| Inject a cubit into another cubit | Parent widget `BlocListener` or `simple_refresh_bus` |
| Forget to `cancel()` a stream subscription in `close()` | Override `close()`, cancel, then `super.close()` |
| `throw failure;` from inside a cubit method | `emit(...failure state...); addError(failure, StackTrace.current);` |
