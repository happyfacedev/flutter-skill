---
name: unit-testing
description: Internal flutter-skill pattern — invoked via the flutter-skill router, not from this description. (Unit and bloc tests — blocTest, mocks vs fakes, streams.)
---

# Unit Testing

Stack: `flutter_test` + `bloc_test` + `mocktail`. No code generation for tests, no mockito. Tests are plain Dart files that `flutter test` discovers; each source file `foo.dart` maps to `foo_test.dart` at the mirror location under `test/`.

> **Placeholder note:** templates use `package:your_app/...`, `Thing`/`ThingsRepository`, `<feature>`, AND `BlocStatus.*` as placeholders — real states may use a bespoke status enum, and the one-shot field may be named `error` or `failure`; rename consistently across state, cubit, and tests. Recompute relative-import depth (`../`) for your file's actual location — never copy a template's literal path.

## What to test — and what not to

**Test (the logic layers):**
- Cubits — every public method: success path + failure path. Per-`Failure`-subtype tests **only when the cubit branches on the subtype**; a pass-through cubit gets one representative — classification belongs to the repository-`Impl` test. Guards follow the **source**, not the templates (templates are minimal skeletons): an `isClosed` test for every method whose emit is reachable after an async suspension — a direct `await`, **or** a debounce/timer hop inside a helper it calls (setters sharing one identical debounce+guard mechanism need a single representative `isClosed` test — but read each to confirm it carries the guard; a missing one is a source defect); a loading-guard test wherever the source implements one — including on-mount `load()` — or cubit-creation Rule 1 / form-creation Rule 3 mandates one (a missing mandated guard is a defect to surface). A guard whose return contract is undefined (a non-void method with no natural no-op value) is a user design question — never invent the contract in a test. A pure synchronous mutation setter (a toggle with no repository call, no failure path) gets a single `expect:`-only transition test
- Repository `Impl`s — response→model mapping and error→`Failure` translation, through the mocked leaf client (for Supabase: the `FeatureApi` seam — [templates/repository_impl_test.dart](templates/repository_impl_test.dart)). Reactive Impls also test the write-through contract: success pushes into `watchX()` (assert the emission and the cache), failure pushes nothing (assert zero emissions)
- Failure classes — error-code→failure mapping where nontrivial
- Formz inputs — each validator branch
- States — `copyWith` field preservation + one-shot error semantics ([templates/state_test.dart](templates/state_test.dart)); form states also test the submit-gating predicate (`isFormValid`) across its branches
- Pure Dart utilities (parsers, formatters, mappers)

**Don't unit test:** generated files (`*.g.dart`, `*.freezed.dart`, retrofit/injectable output), widgets and pages (widget testing is a separate concern, not this pattern), GoRouter wiring, DI registration.

**Coverage:** no numeric gate. The bar is: **every failure branch of the logic layers has a test.** If the project collects coverage, exclude generated code — never chase a global percentage across widgets.

## Test doubles — which kind where

| Dependency | Double |
|---|---|
| Leaf I/O client (Dio/retrofit API, a feature's Supabase `FeatureApi` seam) | mocktail `Mock` — the failure-default is the **thrown transport exception** (`thenThrow`), which `safeCall` converts |
| Plain Future-only repository (no streams) | mocktail `Mock` |
| Plain synchronous collaborator (context/local-state holder, no I/O) | real instance — constructing it is cheaper and truer than mocking |
| Reactive repository (`watchX()` streams) | mocktail `Mock` whose `watchX()` returns a test `StreamController`'s stream ([templates/watching_cubit_test.dart](templates/watching_cubit_test.dart)); for multi-consumer or stateful scenarios, a **fake** — in-memory implementation driving a real subject ([templates/fake_repository.dart](templates/fake_repository.dart)) |
| `SupabaseClient` | **NEVER mock it** — mocked Postgrest builders can't resolve to response data, so the mapping path is unreachable (mechanism + #714 in reference.md). Cubit tests double the repository; **Impl tests mock the feature's `FeatureApi` seam** ([templates/repository_impl_test.dart](templates/repository_impl_test.dart)) — extract the seam first if the Impl takes the raw client (network-creation-supabase sanctions this). `mock_supabase_http_client`: plain CRUD only (no auth/realtime/storage/RPC; pre-1.0 — pin it) |

Cubits receive doubles by constructor — never through `getIt` in tests.

## Critical Rules (Never Break)

1. **`blocTest` for state transitions; plain `test()` for everything else** (initial state, repositories, utilities). *Why:* cubits emit **synchronously** — a listener attached after the method call has already missed every state. `blocTest` subscribes before running `act`. If you ever hand-roll a stream assertion, `expectLater(cubit.stream, emitsInOrder([...]))` must be set up BEFORE the method call, never after.

2. **`expect:`, `verify:`, and `errors:` assert different concerns — one per test.** *Why:* one test, one reason to fail; conflating them makes state-shape refactors break side-effect tests and vice versa. Loading-guard tests are `verify`-only by nature: a cubit never re-emits a value-equal state, so an unguarded cubit's `expect:` list looks identical to a guarded one's — only `verify(...).called(1)` can prove the guard (see reference.md). The rule is `blocTest`-scoped: a plain write-through `test()` asserting a mutation's returned value + stream push + cache together is asserting one behavior — and a guard-rejection test may pair `expect: []` with `verifyNever(...)`, since "the action was rejected" is one behavior.

3. **Never assert inside `fold`; never use `isLeft`/`Left(...)`/`Right(...)` matchers.** Destructure through the shared helpers — `expectSuccess(result)` / `expectFailure(result)` at `test/helpers/result.dart` ([templates/result_helpers.dart](templates/result_helpers.dart)) — then assert on the extracted value. *Why:* an assertion inside a `fold` callback passes vacuously when the other branch runs; and wrapper-specific idioms churn when the stack migrates from dartz `Either` to sealed `Result`. The helper is the only file that touches the wrapper API — the migration edits one file, not every test. Scope: the helpers are for tests that assert on a returned `Either` directly (repository `Impl`s, utilities) — a cubit-only suite that never touches an `Either` doesn't create them.

4. **Failure is the default stub; success is the per-test override.** In `setUp`, stub repository methods to return the failure case; override with success inside individual tests. One test per `Failure` subtype. Expected failures are **values** — never `throwsA` (reserve `throwsA` for genuine programmer errors like asserts). *Why:* failure-default makes an untested failure path impossible to miss — a new test without an explicit success stub fails loudly instead of green-washing. For a **leaf-client** double the failure-default is the exception the transport wrapper catches (`thenThrow(PostgrestException(...))`, `DioException`) — `safeCall` converts it; the no-`throwsA` rule governs assertions on returned failures, not transport stubbing.

5. **Streams are driven, never faked in time.** Push into a real `StreamController.broadcast` (or the fake repo's subject), then `await pumpEventQueue()` before asserting. Never wrap `BehaviorSubject`-fed code in `fakeAsync` (rxdart #395 — it misbehaves). Never push errors into a `watchX()` stream in tests — streams are data-only by architecture; failure paths are tested on the request path via Rule 3/4. Impl-side inversion: when the unit under test OWNS the subject, do listen to its stream — assert the push on success and **zero emissions** on the failure path.

6. **No real time in tests.** No `Future.delayed` waits. Timers/debounce → `fake_async` with explicit `elapse`. `blocTest`'s `wait:` only when the duration is a named constant in the code under test — never a guessed magic number.

7. **`registerFallbackValue` in `setUpAll` — one per non-primitive type used with `any()`/`captureAny()`,** including one per concrete generic instantiation (`ThingKey<String>` and `ThingKey<int>` each need their own). Project-wide fallbacks live in `test/helpers/` and are registered once by `flutter_test_config.dart` ([templates/test_config.dart](templates/test_config.dart)).

8. **Fresh doubles per test; disciplined teardown.** Mocks and stream controllers are created in `setUp` (or `build:`), never shared across tests. In `tearDown`: close the cubit first, then the controller. *Why:* mocktail `when`/`verify` state accumulates across tests; shared doubles make failures order-dependent. Closing controller-before-cubit races the subscription cancel.

## Test shapes

- [templates/cubit_test.dart](templates/cubit_test.dart) — **request-path cubit** (calls repository methods): failure-default stubs, success overrides, `seed:`, plus the loading-guard and `isClosed`-guard tests
- [templates/watching_cubit_test.dart](templates/watching_cubit_test.dart) — **the canonical shape for `StreamSubscriber` cubits** (subscribe-in-constructor). `blocTest`'s single-`act` model does not fit constructor subscriptions — stream reactions use plain `test()` + controller pushes + `pumpEventQueue()` + direct `cubit.state` assertions. Most watching cubits are **hybrids**: request-path methods still get `blocTest` (transitions, `errors:`) in the same file — mixing styles is safe and expected; guards use the plain-`test()` `Completer` form, and a one-shot failure field gets one `seed:`-based stale-failure-clearing `blocTest` (all shown in the template)
- [templates/state_test.dart](templates/state_test.dart) — `copyWith` preservation and one-shot error semantics
- [templates/fake_repository.dart](templates/fake_repository.dart) — in-memory fake of a reactive repository, for multi-consumer scenarios and widget-layer reuse
- [templates/repository_impl_test.dart](templates/repository_impl_test.dart) — **repository `Impl` test**: mock the `FeatureApi` seam, real `safeCall` + error registry, fixture-driven mapping tests, `thenThrow` failure-default; reactive Impls add the write-through group
- [templates/form_cubit_test.dart](templates/form_cubit_test.dart) — **form cubit test**: debounced setters via `fake_async` + plain `test()` (never `blocTest` for the debounce hop), re-entry guard, `errors: () => []` suppression, seeded `isClosed`
- [templates/fixtures.dart](templates/fixtures.dart) — `fixture()`/`fixtureJson()` loaders; fixtures live at `test/fixtures/<feature>/*.json`
- [templates/helpers.dart](templates/helpers.dart) — the `test/helpers/helpers.dart` barrel every test file imports

## Workflow

1. **List the behaviors first.** Before writing any test code, write the plan — one line per test: each public method × (success + each `Failure` subtype), stream reactions, the guards. Every line becomes a `test`/`blocTest` description; this is also how you notice untestable code.
2. Create the mirror file under `test/`. If a non-compliant test file already exists at the mirror path, rewrite it to the skill shape — rules outrank neighboring code.
3. Pick doubles from the table. Create the shared helpers **this suite actually uses**, once, from the templates: the `test/helpers/helpers.dart` barrel plus `mocks.dart`/`builders.dart` as needed; `result.dart` only when a test asserts on an `Either` directly; `fallbacks.dart` only when a non-primitive `any()`/`captureAny()` exists — named `String`/primitive args never need one (an empty registrar is noise; add the file when the first fallback is needed). If `test/flutter_test_config.dart` already exists, **merge** the `registerFallbacks()` call into its `testExecutable` — never overwrite an existing config; it usually carries load-bearing global setup. Creating `test/helpers/` for the first time does **not** obligate migrating pre-existing non-compliant test files — rewrite only the mirror file of the unit under test (step 2); the rest converge as they're touched.
4. Write the tests from the matching template.
5. **Run `flutter test <path>` — tests must compile and pass before the work is done.** A failing test means either the test is wrong (fix it) or the source violates a kit convention (report the violation explicitly — never bend the test to encode defective behavior as expected). Also report violations you notice while *reading* source, even when no test can fail on them.
6. Never deliver skipped tests, commented-out assertions, or assertions on emission order the state machine doesn't guarantee.

## Checklist

- [ ] Test file at the mirror location; one source file → one test file
- [ ] Behavior list covers success + failure paths (per-subtype only where the cubit branches on subtype) + the guards the source mandates; each line is a test
- [ ] Guard tests are `verify`-only; an existing `flutter_test_config.dart` was merged into, never overwritten
- [ ] Doubles follow the table — no mocked `SupabaseClient`, mocks constructed per test
- [ ] Result assertions only via `test/helpers/result.dart`; zero `fold`/`Left`/`Right`/`isLeft` in test bodies
- [ ] Failure-default stubs in `setUp`; success overridden per test
- [ ] Streams: real controller + `await pumpEventQueue()`; no `fakeAsync` near `BehaviorSubject`; no errors pushed on watch streams
- [ ] `registerFallbackValue` in `setUpAll` (one per concrete generic instantiation)
- [ ] `tearDown` closes cubit, then controllers
- [ ] `flutter test <path>` passes; source convention violations reported, not encoded

See [reference.md](reference.md) for `blocTest` parameters, mocktail patterns, test-data builders, fixtures, and the common-mistakes table.
