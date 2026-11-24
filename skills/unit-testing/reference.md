# Unit Testing — reference

## blocTest parameters

| Param | Use for | Notes |
|---|---|---|
| `build:` | construct the cubit with doubles | fresh mocks per test — construct doubles in `setUp`, cubit here |
| `setUp:` | per-test stub overrides | this is where the success-case `when(...)` override goes |
| `seed:` | precondition state | preferred over driving multiple `act` calls to reach a state |
| `act:` | the single method under test | one behavior per test |
| `expect:` | emitted states, in order, by `==` | does NOT include the seed/initial state |
| `skip:` | drop leading emissions | prefer asserting the full list; use only to skip noisy init emissions |
| `wait:` | settle a documented duration | only for named constants in the source (e.g. `SearchCubit.debounce`) — never guessed |
| `verify:` | side effects (`verify(() => repo.save(x)).called(1)`) | in a separate test from `expect:` |
| `errors:` | uncaught errors routed to `addError` | for asserting the `addError(failure, ...)` reporting path |

`blocTest` compares states by `==` — states are Equatable per the kit, so full-value equality lists are the norm. Reserve `isA<State>().having(...)` / `predicate<State>(...)` for the rare field that breaks value equality; never build whole suites on predicates. Formz `.error` values assert by direct equality (deterministic enums/lists); reserve `isA<>` for failure hierarchies. Single-rule inputs assert the exact error; multi-rule (`List<E>`) inputs assert the full list, or `containsAll` for the every-rule-fails branch.

**Loading-guard tests are `verify`-only.** A cubit never re-emits a value-equal state, so an unguarded cubit's emissions de-duplicate into the same `expect:` list a guarded cubit produces (`[loading, success]` either way) — the `expect:` half of a guard test proves nothing. Only `verify(() => repo.load()).called(1)` distinguishes guarded from unguarded.

**Asserting `addError`.** `bloc_test` captures `addError` calls but only asserts them when `errors:` is provided — an `expect:`-only test does NOT fail when the cubit reports errors, so the reporting path needs its own `blocTest` with `errors:`. To assert a branch SUPPRESSES reporting, use `errors: () => []` — the empty list asserts zero uncaught errors. This works in watching-cubit test files too (mixing `blocTest` and plain `test()` in one file is safe). If a plain-`test()` assertion is ever unavoidable, install a recording `BlocObserver` BEFORE constructing the cubit — `BlocBase` captures `Bloc.observer` at construction time; an observer installed after construction silently sees nothing.

**Teardown ordering.** `addTearDown` callbacks run before the group's `tearDown`, so `addTearDown(cubit.close)` per test + a group `tearDown(() => controller.close())` yields cubit-then-controller — the required order. Repository-owned subjects invert the roles, same mechanics: cancel test subscriptions per test (`addTearDown(sub.cancel)`), close the repo in the group `tearDown(() => repository.dispose())`.

## mocktail patterns

```dart
class MockThingsRepository extends Mock implements ThingsRepository {}

// Stub — async method returning Either:
when(() => repository.loadThings())
    .thenAnswer((_) async => const Left(ThingsLoadFailure()));

// Stub — stream getter:
when(() => repository.watchThings()).thenAnswer((_) => controller.stream);

// Argument matchers (need fallbacks for non-primitives, see below):
when(() => repository.updateThing(any())).thenAnswer((_) async => Right(thing));
verify(() => repository.updateThing(any(that: isA<Thing>()))).called(1);

// Capture:
final captured = verify(() => repository.updateThing(captureAny())).captured;
```

- `thenAnswer` for anything async or computed; `thenReturn` only for plain sync values. `thenReturn` on a `Future`/`Stream` method is a runtime error.
- `verifyNever(() => repository.deleteThing(any()))` asserts a call did NOT happen.
- Group shared mock declarations in `test/helpers/mocks.dart` (one `class MockX extends Mock implements X {}` per doubled type) — test files import the barrel instead of redeclaring.

### registerFallbackValue

Needed once per non-primitive type used with `any()`/`captureAny()` — mocktail must synthesize a placeholder of that type. Generic types need one per concrete instantiation. Keep a single `registerFallbacks()` function in `test/helpers/fallbacks.dart`, called from `flutter_test_config.dart`, so individual test files never repeat it. Symptom of a missing fallback: `Bad state: A test tried to use 'any' or 'captureAny' but registerFallbackValue was not previously called`.

## Test data: builders and fixtures

- **Object mothers** — top-level factory functions with named params and sensible defaults. Start inline next to the tests that use them; promote to `test/helpers/builders.dart` at the second consumer (mirror of the promote-on-reuse principle):
  ```dart
  Thing buildThing({String id = 'thing-1', String name = 'Thing', bool archived = false}) =>
      Thing(id: id, name: name, archived: archived);
  ```
  Tests then state only what matters: `buildThing(archived: true)`.
- **Fixtures** — raw JSON payloads for repository-`Impl` mapping tests live in `test/fixtures/<feature>/*.json`; load with the `fixture()`/`fixtureJson()` helpers ([templates/fixtures.dart](templates/fixtures.dart), lives at `test/helpers/fixtures.dart`; paths resolve from the package root — `flutter test`'s cwd). Keep fixture JSON byte-identical to real backend responses — that is the point of the test. Fixtures cover realistic success payloads; malformed/synthetic edge rows stay inline literals in the test that needs them.

## Async settling — decision table

| Situation | Do |
|---|---|
| Pushed into a stream, need the cubit to have reacted | `await pumpEventQueue();` |
| Awaited repo call inside `act:` | nothing — `blocTest` awaits `act` |
| Debounce/throttle/timer in the unit | `fake_async`: `fakeAsync((async) { ...; async.elapse(duration); ... })` |
| `BehaviorSubject` anywhere in the path | do NOT use `fake_async` (rxdart #395) — drive the subject directly + `pumpEventQueue` |
| Tempted to `await Future.delayed(...)` | stop — pick one of the above |

`fake_async` must be a **declared** dev_dependency to import it (it arrives transitively via flutter_test, but transitive deps aren't importable) — add it when the first debounce/timer test appears. Its transitively-locked version is NOT a valid direct-constraint floor (`pub` will fail to solve it), so run `flutter pub add --dev fake_async` rather than copying the locked version.

Debounce duration needs one referenceable source of truth. When the cubit owns it, expose a public named constant (`static const debounce = ...`, see form-creation) and `elapse(TheCubit.debounce)`. When it lives inside a shared `Debouncer` util, don't duplicate it on the cubit (two constants drift) — declare a local `const` in the test citing the util's `file:line` it mirrors. Never a bare unexplained number.

## Running tests

```bash
flutter test                                   # whole suite
flutter test test/features/<feature>/          # one directory
flutter test test/.../thing_cubit_test.dart    # one file
flutter test --plain-name "emits failure"      # single test by name
flutter test --reporter expanded               # verbose per-test output
flutter test --coverage                        # coverage/lcov.info (exclude generated code downstream)
```

## Common mistakes

| Mistake | Why it's wrong | Fix |
|---|---|---|
| `result.fold((f) => fail(...), (v) => expect(v, ...))` in a test body | passes vacuously if you forget `fail` in one arm; unreadable failure output | `final v = expectSuccess(result); expect(v, ...)` |
| `expect(result, Left(XFailure()))` | dartz-specific; churns on the sealed-`Result` migration | `expect(expectFailure(result), isA<XFailure>())` |
| `throwsA(isA<XFailure>())` for an expected failure | kit failures are values, never thrown — the test documents the wrong contract | assert the returned failure value |
| Asserting states after calling the cubit method in a plain `test()` | cubits emit synchronously; the states are already gone | `blocTest`, or `expectLater` BEFORE the call |
| `expect:` list includes the initial/seeded state | `blocTest` only records emissions after `act` starts | drop it from the list |
| `wait: Duration(milliseconds: 300)` guessed | brittle magic number; hides a race | reference the source's named constant, or `fake_async` |
| `fakeAsync` around a `BehaviorSubject`-fed cubit | rxdart #395 — subject misbehaves under FakeAsync | drive the subject synchronously + `pumpEventQueue` |
| `Stream.error(...)` pushed into a `watchX()` test stream | our streams are data-only by architecture; the test asserts an impossible path | test the failure on the request path (`loadX` returns `Left`) |
| Mocking `SupabaseClient` | mocked Postgrest builders can't resolve to data — the success/mapping path is unreachable (and mockito setups hit the 30s timeout, #714) | cubit tests: double the repository; Impl tests: mock the `FeatureApi` seam (templates/repository_impl_test.dart) |
| Shared mock instance across tests | `when`/`verify` state accumulates; order-dependent failures | fresh mocks in `setUp` |
| Controller closed before cubit in teardown | races the `StreamSubscriber` cancel; intermittent errors | `await cubit.close()` first, then `controller.close()` |
| Asserting `verify` and `expect:` in one `blocTest` | two reasons to fail; refactors break both | split into a state test and a side-effect test |
| `expect:` half in a loading-guard test | value-equal de-dup makes it pass with or without the guard | guard tests are `verify(...).called(1)`-only |
| Overwriting an existing `flutter_test_config.dart` | clobbers load-bearing global setup (theme fallbacks, etc.) | merge `registerFallbacks()` into the existing `testExecutable` |
| Creating an empty `fallbacks.dart` "for compliance" | unused-import lint noise, dead file | create it when the first non-primitive `any()` appears |
| Copying a template's literal `../../../helpers/helpers.dart` import | template nesting differs from your file's location | recompute the `../` depth for your actual path |
