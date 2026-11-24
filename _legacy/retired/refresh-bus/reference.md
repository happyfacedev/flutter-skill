# Refresh Bus — Reference

## Producer side: `push<T>` vs `refresh<T>`

The package exposes two emission methods:

- `RefreshBus.instance.push<T>(value)` — emits a typed payload. Subscribers receive it via `onData<T>(callback)`. **Use this for almost everything** — even zero-payload events benefit from typed dispatch.
- `RefreshBus.instance.refresh<T>()` — emits a type-only signal with no payload. Subscribers receive it via `onRefresh<T>(callback)`.

This project uses `push<T>` exclusively because the typed-payload form covers both cases (a zero-payload event is just `const FeatureListChanged()` passed to `push`). Keeping a single emission method avoids the "did I subscribe with `onData` or `onRefresh`?" trap.

## Subscriber side: lifecycle

The `RefreshBusSubscriber<State>` mixin:
- Registers each `onData<T>` / `onRefresh<T>` call you make in the constructor
- Tracks the subscriptions internally
- Cancels them when the cubit's `close()` runs

You don't need a `StreamSubscription` field. You don't need to override `close()`. You don't need to call `super.close()` for subscription cleanup. The mixin's `close()` does both.

If you override `close()` for other cleanup (a Postgres realtime channel, a timer, etc.), call `super.close()` at the end — that's where the mixin cancels its subscriptions.

## Multiple events in one subscriber

One `onData<T>` call per event type the cubit consumes. No `is` checks, no `switch` on a sealed base.

```dart
class ItemsSummaryCubit extends Cubit<ItemsSummaryState>
    with RefreshBusSubscriber<ItemsSummaryState> {
  ItemsSummaryCubit(this._repo, this._ctx)
      : super(const ItemsSummaryState()) {
    onData<ItemsChanged>((event) {
      if (event.organizationId != _ctx.currentOrganizationId) return;
      unawaited(load());
    });
    onData<OrganizationChanged>((_) => unawaited(load()));
    onData<UserOrganizationsChanged>((_) => unawaited(load()));
  }
  // ...
}
```

## Payload filtering

Filtering by type is automatic via the `<T>` parameter. Filtering by payload is the cubit's responsibility — happens inside the callback.

```dart
// Type-only filter (every ItemsChanged triggers reload):
onData<ItemsChanged>((_) => unawaited(load()));

// Type + payload filter (only events for the current organization):
onData<ItemsChanged>((event) {
  if (event.organizationId != _scope.currentOrganizationId) return;
  unawaited(load());
});

// Type + multiple payload filters:
onData<ItemChanged>((event) {
  final current = state.detail;
  if (current == null) return;
  if (event.itemId != current.itemId) return;
  if (event.organizationId != current.organizationId) return;
  unawaited(refresh());
});
```

Don't optimize prematurely. Start with type-only filtering; add payload checks only when profiling shows wasted reloads or when the reload itself is expensive.

## Adding a new event

1. **Decide where it lives.** Cross-feature events (consumed by features other than the one that emits) → `lib/core/events/refresh_events.dart`. Feature-internal events (the same feature emits and consumes) → don't use the bus at all; coordinate directly within the feature.

2. **Define the class** at the bottom of `refresh_events.dart`:
   ```dart
   final class FeatureXChanged {
     const FeatureXChanged({required this.scopeId});
     final String scopeId;
   }
   ```
   Naming: past-tense verb + noun (`ItemsChanged`, `OrderSubmitted`). Not imperative (`RefreshItems` is wrong — that's a method name, not an event).

3. **Producers** import and `push`:
   ```dart
   import 'package:simple_refresh_bus/simple_refresh_bus.dart';
   import 'package:your_app/core/events/refresh_events.dart';
   // ...
   RefreshBus.instance.push<FeatureXChanged>(
     FeatureXChanged(scopeId: scopeId),
   );
   ```

4. **Subscribers** mix in `RefreshBusSubscriber<State>` and `onData<FeatureXChanged>`.

5. **Document the new event** — add a doc comment on the class describing when it fires and how subscribers filter. The existing events in `refresh_events.dart` are the precedent.

## Testing cubits that use the bus

The bus is a process-wide singleton. Two patterns — full templates and walkthroughs live in the `unit-testing` skill:

- **Producer side** — subscribe via `RefreshBus.instance.onDataStream<T>()` in the test's `setUp`, capture events into a list, assert in `verify`. Always `cancel` the subscription in `tearDown` so events don't leak between tests. See `unit-testing/templates/producer_cubit_test.dart`.
- **Subscriber side** — push events from `act:` via `RefreshBus.instance.push<T>(...)`, use `wait:` to let the cubit's `unawaited(load())` settle. See `unit-testing/templates/streaming_cubit_test.dart`.

Two API names to keep straight:
- `RefreshBus.instance.onDataStream<T>()` — the bus's `Stream<T>` for external subscribers (tests).
- `onData<T>(callback)` — the `RefreshBusSubscriber` mixin's helper for cubits.

Both deliver the same events; they're just different surface APIs for different audiences.

## Common mistakes

| ❌ Don't | ✅ Do |
|----------|-------|
| `_refreshBus.emit(...)` (old local API) | `RefreshBus.instance.push<T>(...)` |
| Inject `RefreshBus` via constructor | Use the singleton — `RefreshBus.instance` |
| Subscribe to a stream with `.listen()` | Mix in `RefreshBusSubscriber<State>`; use `onData<T>` |
| Override `close()` just to cancel a refresh-bus subscription | The mixin handles it |
| `if (event is FeatureChanged)` inside one big handler | One `onData<T>` per type |
| Push one giant "everything changed" event | One event per affected concern |
| Subclass an event with a sealed hierarchy | Plain `final class` per event type |
| Emit events on `setUp` / `build` of a test | Use `act:` in `blocTest` so the build is clean first |
| Use `RefreshBus.instance.refresh<T>()` for events with data | Use `push<T>` consistently |

## File layout

```
lib/core/events/
└── refresh_events.dart      # All cross-feature event classes — one file

lib/features/<feature>/logic/cubit/
├── <feature>_cubit.dart     # Producer: imports simple_refresh_bus + events,
│                            #   calls RefreshBus.instance.push<T>(...)
└── <other>_cubit.dart       # Subscriber: `with RefreshBusSubscriber<State>`,
                             #   `onData<T>(...)` in constructor
```
