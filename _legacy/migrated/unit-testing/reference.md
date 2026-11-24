# Unit Testing — Reference

## `blocTest` parameters

```dart
blocTest<MyCubit, MyState>(
  'description of the behavior',
  setUp: () { ... },                 // optional — runs before build; configure mocks here
  build: () => MyCubit(repository),  // required — returns a fresh cubit
  seed: () => const MyState(...),    // optional — initial state instead of cubit's default
  act: (cubit) => cubit.doThing(),   // optional — interact with the cubit
  wait: const Duration(milliseconds: 50),  // optional — delay after `act` before assertions
  expect: () => [                    // optional — exact list of emitted states (after seed)
    isA<MyState>().having((s) => s.status, 'status', BlocStatus.loading),
    isA<MyState>().having((s) => s.status, 'status', BlocStatus.success),
  ],
  errors: () => [isA<SomeFailure>()],  // optional — verify addError() was called
  verify: (cubit) {                  // optional — final assertions on cubit / mocks
    verify(() => repository.fetch()).called(1);
  },
);
```

Key callbacks ordering: `setUp` → `build` → `seed` (if any) → `act` → `wait` → `expect` matched → `verify` → cubit closed.

## `expect:` matchers

Use `isA<MyState>().having(...)` rather than reconstructing the expected state — it's clearer when only some fields matter:

```dart
isA<MyState>()
    .having((s) => s.status, 'status', BlocStatus.success)
    .having((s) => s.data?.id, 'data.id', '1')
```

Use `equals(const MyState(...))` for whole-state comparisons. Requires the state to have value equality (Equatable or const-canonicalized).

## Mocktail patterns

### Stubbing

```dart
class MockRepository extends Mock implements FeatureRepository {}

late MockRepository repo;
setUp(() => repo = MockRepository());

// Sync return:
when(() => repo.method()).thenReturn(value);

// Async return:
when(() => repo.fetch()).thenAnswer((_) async => const Right([]));

// Conditional on argument:
when(() => repo.fetchById('123')).thenAnswer((_) async => const Right(...));
when(() => repo.fetchById(any())).thenAnswer((_) async => const Left(NotFoundFailure()));

// Throws:
when(() => repo.foo()).thenThrow(Exception('boom'));
```

### Argument matchers

```dart
when(() => repo.foo(any())).thenAnswer(...);                // any positional
when(() => repo.foo(any(named: 'id'))).thenAnswer(...);     // any named arg
when(() => repo.foo(captureAny())).thenAnswer(...);         // capture for later inspection
when(() => repo.foo('exact')).thenAnswer(...);              // literal match takes precedence
```

`any()` requires a fallback for non-primitive types — see `registerFallbackValue` below.

### Verification

```dart
verify(() => repo.method()).called(1);                      // called exactly once
verify(() => repo.method(any())).called(greaterThan(0));    // called at least once
verifyNever(() => repo.method());                           // never called
verifyInOrder([                                             // ordered sequence
  () => repo.start(),
  () => repo.commit(),
]);

// Capture an argument for assertions:
final captured = verify(() => repo.foo(captureAny())).captured;
expect(captured.single, equals('expected'));
```

## `registerFallbackValue`

Mocktail can't auto-generate defaults for non-primitive types. Without a fallback, `when(() => repo.foo(any<NonPrimitive>()))` throws at setup. Register once per test file in `setUpAll`:

```dart
setUpAll(() {
  registerFallbackValue(const GenericFailure());
  registerFallbackValue(FooRequestBody(id: 'fallback'));
  registerFallbackValue(DateTime(2000));
  registerFallbackValue(StackTrace.empty);
});
```

A common project pattern is to extract these into a single `registerProjectFallbacks()` helper called from every test file's `setUpAll` — see [templates/mocktail_setup.dart](templates/mocktail_setup.dart).

## Fixtures: const vs non-const models

Freezed models with primitive-only fields can be `const`-constructed inline in stubs:

```dart
when(() => repo.fetchUser()).thenAnswer(
  (_) async => const Right(UserResponse(id: 'u1', name: 'Alice')),
);
```

Models with `DateTime`, `List`, `Map`, `Uri`, or any non-`const`-able field can NOT be `const`. Lift the fixture to a top-level `final` variable:

```dart
final tItem = ItemResponse(
  id: 'i1',
  startsAt: DateTime(2024, 1, 1, 18),
);

// inside the test:
when(() => repo.fetch()).thenAnswer((_) async => Right([tItem]));
```

Top-level `final` (or `static final` on a `class Fixtures {}`) gives the same reuse across tests as `const` would.

## Stubbing repository methods that return `Either<Failure, T>`

```dart
import 'package:dartz/dartz.dart';

// Success path:
when(() => repo.fetchThing(id: 'a')).thenAnswer(
  (_) async => const Right(FeatureResponse(id: 'a', name: 'A')),
);

// Failure path:
when(() => repo.fetchThing(id: 'b')).thenAnswer(
  (_) async => const Left(FeatureNotFoundFailure()),
);

// Transport failure:
when(() => repo.fetchThing(id: 'c')).thenAnswer(
  (_) async => const Left(FeatureNetworkFailure()),
);
```

Pass the concrete `Right(...)` / `Left(...)` — don't try to `any<Either<...>>()` for the return value (it works, but obscures intent).

## Bus singleton — what tests need to know

`RefreshBus.instance` is process-wide. Tests in the same isolate share it. Two consequences:

- **Subscriber tests:** if you push an event in `act`, the same event reaches every subscriber created during the test (and any leftover from a prior test that didn't clean up). Each test creates a fresh cubit via `build:`, so its own subscribers are isolated, but `onDataStream<T>` subscribers in test code persist until `tearDown` cancels them.
- **Producer tests:** when you subscribe via `RefreshBus.instance.onDataStream<T>()` inside `setUp` to capture pushed events, ALWAYS cancel the subscription in `tearDown`. Otherwise the next test's `capturedEvents` list (or unrelated push assertions) will see events from prior tests.

The package doesn't expose a "reset" — discipline at `tearDown` is the contract.

## Two cubit-test shapes for refresh-bus

The bus has two sides; each needs a different test shape.

### Subscriber side: push events into the cubit

The cubit mixes in `RefreshBusSubscriber<State>`. The test pushes an event on `RefreshBus.instance.push<T>(...)` from `act`; the cubit's `onData<T>` callback fires; assert the resulting state changes.

```dart
blocTest<FeatureCubit, FeatureState>(
  'reloads when OrganizationChanged for current organization arrives',
  setUp: () => when(() => repo.fetch()).thenAnswer((_) async => const Right([])),
  build: () => FeatureCubit(repo, ctx),
  act: (_) => RefreshBus.instance.push<OrganizationChanged>(
    const OrganizationChanged(organizationId: 'org-1'),
  ),
  wait: const Duration(milliseconds: 50),    // see "wait: caveat" below
  expect: () => [
    isA<FeatureState>().having((s) => s.status, 'status', BlocStatus.loading),
    isA<FeatureState>().having((s) => s.status, 'status', BlocStatus.success),
  ],
);
```

Prefer the `wait:` parameter over `await Future.delayed(...)` in `act` — `blocTest` ties the wait to its state-collection lifecycle. They're functionally similar; `wait:` reads cleaner.

### Producer side: capture pushed events

The cubit calls `RefreshBus.instance.push<T>(...)` in its method. The test subscribes via `RefreshBus.instance.onDataStream<T>()` in `setUp`, collects events into a list, and asserts in `verify`. See [templates/producer_cubit_test.dart](templates/producer_cubit_test.dart) for the full shape.

```dart
late List<UserOrganizationsChanged> captured;
late StreamSubscription<UserOrganizationsChanged> sub;

setUp(() {
  captured = <UserOrganizationsChanged>[];
  sub = RefreshBus.instance.onDataStream<UserOrganizationsChanged>().listen(captured.add);
});

tearDown(() async { await sub.cancel(); });

blocTest<LeaveOrganizationCubit, LeaveOrganizationState>(
  'pushes UserOrganizationsChanged on success',
  setUp: () => when(() => repo.leaveOrganization(organizationId: 'org-1'))
      .thenAnswer((_) async => const Right(unit)),
  build: () => LeaveOrganizationCubit(repo),
  act: (cubit) => cubit.leave(organizationId: 'org-1'),
  wait: const Duration(milliseconds: 50),
  expect: () => [...],
  verify: (_) {
    expect(captured, hasLength(1));
  },
);
```

Two API names to keep straight:
- `RefreshBus.instance.onDataStream<T>()` — the singleton's `Stream<T>` for external subscribers (tests).
- `onData<T>(callback)` — the `RefreshBusSubscriber` mixin's helper for cubits.

Both deliver the same events; they're just different surface APIs.

## `wait:` — what to use, what to avoid

| Situation | Use |
|---|---|
| `unawaited(load())` inside an event listener | `wait: const Duration(milliseconds: 50)` |
| Verifying a side effect on a broadcast stream | `wait: const Duration(milliseconds: 50)` |
| Debounced inputs | `wait:` longer than the debounce window |
| Purely synchronous `act` (no `await`, no streams) | no `wait` needed |

**Caveat:** `wait: 50ms` is a heuristic — fast enough not to slow the suite, long enough for most async chains. On slow CI, intermittent failures may need a longer wait (200–500ms). If a test flakes only on CI, bump the wait before reaching for retries. The pattern is necessary because `simple_refresh_bus` doesn't expose a synchronous flush.

## Verifying error routing (`addError`)

When a cubit calls `addError(failure, StackTrace.current)`, `blocTest`'s `errors:` parameter captures it:

```dart
blocTest<MyCubit, MyState>(
  'routes failure to AppBlocObserver',
  setUp: () => when(() => repo.fetch())
      .thenAnswer((_) async => const Left(NetFailure())),
  build: () => MyCubit(repo),
  act: (cubit) => cubit.load(),
  errors: () => [isA<NetFailure>()],
);
```

Use this when the cubit MUST surface a failure through the global snackbar. For failures that should NOT auto-snackbar (per `failure-modeling`), assert `errors: () => <Object>[]` to lock in that behavior.

## `wait:` — when to set it

Set `wait` when the cubit's `act` triggers async work that `blocTest` can't await directly:
- `unawaited(...)` calls inside event listeners (streaming cubits)
- Subscriptions to streams that take a tick to deliver
- Debounced inputs (set `wait` longer than the debounce window)

Without `wait`, `blocTest` reads the state list before the async work settles → flaky tests.

50ms is the project default for `unawaited(...)`-style cases. Longer for explicit debouncing.

## Running tests

```bash
flutter test                                                # full suite
flutter test test/core/                                     # one directory
flutter test test/core/startup/startup_pipeline_cubit_test.dart   # one file
flutter test --plain-name "completes when all steps pass"  # single test by name
flutter test --reporter expanded                            # verbose
flutter test --coverage                                     # writes coverage/lcov.info
```

Watch mode (re-runs on file change) isn't built into `flutter test` directly — use a wrapper like `entr` or your IDE's test runner.

## Common mistakes

| ❌ Don't | ✅ Do |
|----------|-------|
| `test('cubit emits …', () async { ... await cubit.something(); expect(...); })` | `blocTest<Cubit, State>(...)` — it handles emit-order and disposal |
| Share a `MockRepository` between tests | Create fresh in `setUp` or inside `build:` |
| `when(() => repo.foo(any()))` without `registerFallbackValue` for `foo`'s arg type | Register fallback in `setUpAll` |
| `expect(cubit.state, equals(...))` for a `const` state class without value equality | Use Equatable on the state OR use `having()` matchers |
| Hit a real Supabase / Firebase / HTTP endpoint | Mock the repository / client |
| Push an event on `RefreshBus.instance` in `setUp` (before build) | Push in `act` — `build` happens first |
| Forget `await Future.delayed(...)` after a `RefreshBus.push` | Use `wait:` or `await Future.delayed(...)` in `act` |
| `verify(...)` without `setUp`-time stubbing — the mock will throw on the call | Stub first, act second, verify third |
| Test private (`_`-prefixed) methods directly | Test through the public method that exercises them |
