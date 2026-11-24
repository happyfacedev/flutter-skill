---
name: reactive-repository
description: Internal flutter-skill pattern — invoked via the flutter-skill router, not from this description. (Reactive repositories — shared data streams.)
---

# Reactive Repository

When data is displayed by more than one cubit (different pages, a page plus a badge, a list plus a detail), the owning repository becomes **reactive**: it holds a `BehaviorSubject` cache and exposes a `watchX()` stream. Every interested cubit subscribes; mutations write through the repository, which pushes the fresh value into its own stream — so every subscriber updates automatically, with no re-fetch and no cross-cubit signalling. The repository is simultaneously the **source of truth and the notification channel**.

This replaces event-bus signalling for cross-feature data propagation. It is also the sanctioned mechanism behind cubit-creation Critical Rule 5 (no cubit-to-cubit dependencies).

## When to make a repository reactive

- Two or more independent cubits display the same data
- A mutation in one flow must update state owned by another flow/page
- A late-created cubit needs the current value immediately (BehaviorSubject replays the cached latest)

**Don't** make a repository reactive when:
- The data has a single consumer — the default Future-first repository is simpler; add `watch*` only when the second consumer appears (mirror of "don't promote speculatively")
- The coordination is two cubits on the SAME page — a parent widget `BlocListener` is lighter
- It's auth/theme/permission state — those already live in global cubits

## Critical Rules (Never Break)

1. **Streams carry DATA only — never errors, never loading states.** Failures stay on the request path: `loadX()` and mutations return `Either<Failure, T>` and the *calling* cubit emits its own failure state. *Why:* an error pushed into the subject reaches every subscriber at once and, unhandled, kills their subscriptions; error ownership belongs to whoever initiated the action.

2. **Only the owning repository pushes into its subject.** Mutations follow write-through: call the backend, on success push the updated value (`_things.add(updated)`). No other class touches the subject. *Why:* a single writer keeps every update traceable to one file.

3. **Use `BehaviorSubject` (rxdart), not a plain `StreamController`.** *Why:* it caches and replays the latest value to late subscribers — a cubit created after the last push still receives current data instantly. Seed it (`BehaviorSubject.seeded(...)`) when a sensible initial value exists.

4. **Reactive repositories are `@lazySingleton` — the sanctioned stateful repository.** Holding the cache is their entire point, so the usual "repositories are stateless" framing doesn't apply. Provide a `@disposeMethod` that closes the subject(s). *Why:* a factory-scoped subject would give each consumer a private, permanently-empty stream.

5. **Subscribing cubits use the `StreamSubscriber` mixin** (subscribe in the constructor; the mixin cancels on `close()`). The subscription callback only emits data into state — no async work inside it.

## Anatomy

```dart
@lazySingleton
class ThingsRepository {
  ThingsRepository(this._api);
  // Thin seam over the client (dumb Future<dynamic> methods) — Impl tests
  // mock THIS, never SupabaseClient (see /unit-testing doubles table).
  final ThingsApi _api;

  final BehaviorSubject<List<Thing>> _things = BehaviorSubject();

  Stream<List<Thing>> watchThings() => _things.stream;
  List<Thing>? get currentThings => _things.valueOrNull;

  // Wide seam (Either<Failure, T>): fold(Left.new, ...) propagates transport
  // and auth failures unchanged — never re-narrow to the feature base.
  Future<Either<Failure, Unit>> loadThings() async {
    final result = await SupabaseNetworkHandler.safeCall<dynamic>(_api.getThings);
    return result.fold(Left.new, (data) {
      // Mapping is GUARDED: a malformed row returns Left, never throws —
      // the repository contract is Either, and the Impl test asserts it.
      try {
        _things.add([
          for (final j in data as List<dynamic>)
            Thing.fromJson(j as Map<String, dynamic>),
        ]);
        return const Right(unit);
      } catch (_) {
        return const Left(ThingsFetchFailure());
      }
    });
  }

  Future<Either<Failure, Unit>> updateThing(Thing updated) async {
    final result = await SupabaseNetworkHandler.safeCall<dynamic>(
      () => _api.updateThing(updated.toJson()),
    );
    return result.fold(Left.new, (row) {
      try {
        final fresh = Thing.fromJson(row as Map<String, dynamic>);
        _things.add([
          for (final t in _things.value) t.id == fresh.id ? fresh : t,
        ]);                                          // write-through: push, don't re-fetch
        return const Right(unit);
      } catch (_) {
        return const Left(ThingsFetchFailure());
      }
    });
  }

  @disposeMethod
  void dispose() => _things.close();
}
```

The consuming cubit shape lives in [templates/watching_cubit.dart](templates/watching_cubit.dart): subscribe for data, call `loadThings()` for the initial fetch, render failures from the load/mutation result — never from the stream.

## Templates

- [Reactive repository](templates/reactive_repository.dart) — BehaviorSubject cache + watch/load/write-through mutation + dispose
- [Watching cubit](templates/watching_cubit.dart) — `StreamSubscriber` mixin + data-only subscription + failure handling on the request path
- [StreamSubscriber mixin](templates/stream_subscriber.dart) — lives at `lib/core/utils/stream_subscriber.dart`; create it once per project if absent

## Checklist

- [ ] Repository is `@lazySingleton` with a `@disposeMethod` closing every subject
- [ ] `BehaviorSubject` (seeded where sensible), exposed only as `watchX()` streams — the subject itself stays private
- [ ] Streams carry data only; `loadX()`/mutations return `Either<Failure, T>` for errors
- [ ] Mutations write through: backend call → on success push the updated value into the subject (no subscriber re-fetch)
- [ ] Subscribing cubits use `StreamSubscriber`, subscribe in the constructor, and only `emit` in the callback
- [ ] Repository stays Future-first until a second independent consumer justifies `watch*`
- [ ] Client accessed through a thin `FeatureApi` seam — the Impl's tests mock the seam, never `SupabaseClient`
- [ ] Every mapping site guarded (`try/catch` → fetch failure) — a malformed row returns `Left`, never throws
