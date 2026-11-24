---
name: unit-testing
description: Writes unit and bloc tests using `flutter_test` + `bloc_test` + `mocktail`. Tests mirror the `lib/` directory layout under `test/`, use `mocktail`'s `Mock implements <Type>` for repository / service doubles, and use `blocTest<Cubit, State>` for cubits (with `setUp` / `build` / `act` / `expect` / `wait`). Covers process-status cubits, streaming cubits that subscribe via `RefreshBusSubscriber`, producer cubits that push events on `RefreshBus.instance`, and plain Dart units. Use when adding tests for a new cubit / repository / utility, when the user asks "write tests for", "add a test", "unit test", "bloc test", "mock", or "test coverage".
---

# Unit Testing

The project uses `flutter_test` + `bloc_test` + `mocktail`. No code generation, no `build.yaml` test config — tests are plain Dart files that `flutter test` discovers automatically.

Real reference files to read when you need a worked example:
- `test/core/startup/startup_pipeline_cubit_test.dart` — full bloc_test setup with mocktail mocks, setup helpers, multiple test cases
- `test/core/navigation/deep_link_parser_test.dart` — plain unit test for a pure function
- `test/core/services/auth_shell_context_test.dart` — service with stream + mocked dependencies

## File layout

Tests mirror `lib/` exactly:

```
lib/                          →  test/
├── core/                        ├── core/
│   ├── startup/                 │   ├── startup/
│   │   ├── startup_pipeline_cubit.dart   →   startup_pipeline_cubit_test.dart
│   │   └── ...                  │   │   └── ...
│   └── ...                      │   └── ...
└── features/                    └── features/
    └── <feature>/                   └── <feature>/
        └── logic/                       └── logic/
            ├── cubit/                       ├── cubit/
            └── repositories/                └── repositories/
```

Each source file `foo_bar.dart` maps to `foo_bar_test.dart` in the mirror location. One source file → one test file.

## Critical Rules

1. **Cubit tests use `blocTest<Cubit, State>`, not raw `test()`.** *Why:* `blocTest` handles the boilerplate of creating the cubit, awaiting state stabilization, and comparing emitted-states-by-equality. Raw `test()` for a cubit means writing all that by hand and getting `await`-ordering wrong.

2. **Mock all I/O dependencies with `mocktail` — never hit a real network, file system, Supabase, or Firebase.** *Why:* unit tests must be deterministic, fast, and runnable offline. Real I/O makes tests flaky and CI dependent on external services.

3. **State classes need value equality for `blocTest`'s `expect:` to work.** *Why:* `expect:` compares emitted states to expected ones by `==`. The project's cubit states use either explicit `Equatable` (most cases) or `const` instances with const-canonicalized fields. Without value equality, the matcher compares identity and every test fails.

4. **Register mock fallback values for non-primitive `any()` matchers.** *Why:* mocktail can stub a call like `when(() => repo.foo(any()))` only if it can synthesize a default for the parameter type. Built-in fallbacks exist for primitives; custom types need `registerFallbackValue(YourType(...))` once before the test runs.

5. **Each test creates its own mocks in `setUp` or in the `build:` callback — never share mock instances across tests.** *Why:* mocktail's `when()` configurations and `verify()` counters accumulate across tests. Sharing a mock leaks state between tests and makes failures order-dependent.

## Templates

- [Cubit test](templates/cubit_test.dart) — `blocTest` with mocktail, the standard shape for non-streaming, non-event-producing cubits
- [Streaming cubit test](templates/streaming_cubit_test.dart) — for cubits that subscribe to `simple_refresh_bus` events via `RefreshBusSubscriber`
- [Producer cubit test](templates/producer_cubit_test.dart) — for cubits that push events on `RefreshBus.instance.push<T>(...)`; subscribe via `onDataStream<T>()` in `setUp` to capture pushed events
- [Plain unit test](templates/unit_test.dart) — for pure Dart logic (parsers, formatters, utilities)
- [Mocktail registration](templates/mocktail_setup.dart) — the `registerFallbackValue` calls a project test suite typically needs

> **Placeholder note**: every template uses `package:your_app/...` and `<feature>` as placeholders. Find-and-replace `your_app` → `core_boilerplate` and `<feature>` → your feature name before pasting into a real test file.

## Reference

See [reference.md](reference.md) for:
- `blocTest` parameters: `build`, `setUp`, `act`, `expect`, `wait`, `verify`, `errors`, `seed`
- Mocktail patterns: `when` / `thenAnswer` / `thenReturn` / `verify` / `captureAny` / `verifyNever`
- Stubbing `Either<Failure, T>` returns from a repository
- Testing streaming cubits — pushing events on the real `RefreshBus.instance`
- Verifying error routing (`addError` flow to `AppBlocObserver`)
- `wait:` — when async work needs settling before assertions
- Running tests: CLI commands, focusing on a file / group / single test
- Common mistakes

## Workflow when adding tests for a new cubit

1. Locate the source file (`lib/features/<feature>/logic/cubit/<name>_cubit.dart`).
2. Create the mirror test file at `test/features/<feature>/logic/cubit/<name>_cubit_test.dart`.
3. Identify the cubit's dependencies (constructor parameters). For each, decide: mock with mocktail, fake, or real (rare — only for value-type dependencies).
4. Pick the matching template based on the cubit's shape:
   - Standard cubit (calls repository methods) → `cubit_test.dart`
   - Streaming cubit (mixes in `RefreshBusSubscriber`) → `streaming_cubit_test.dart`
5. Cover the public method surface: one `blocTest` per behavior (success path, each failure type, edge cases).
6. Run the test: `flutter test test/features/<feature>/logic/cubit/<name>_cubit_test.dart`.

## Running tests

```bash
flutter test                                                # the whole suite
flutter test test/core/startup/                             # one directory
flutter test test/core/startup/startup_pipeline_cubit_test.dart   # one file
flutter test --plain-name "completes when all steps pass"  # single test by name
flutter test --reporter expanded                            # verbose per-test output
flutter test --coverage                                     # write coverage/lcov.info
```

## Checklist

- [ ] Test file is at the mirror location of the source file under `test/`
- [ ] All I/O dependencies are mocked (no real network / Supabase / Firebase / file system)
- [ ] Mocks are class-per-test (created in `setUp` or in `build:`); never shared
- [ ] `registerFallbackValue(...)` called once at the top of `main()` for any non-primitive type used with `any()`
- [ ] State class has value equality (Equatable or const) — otherwise `expect:` fails on identity
- [ ] `blocTest` covers the success path AND each failure variant the cubit handles
- [ ] For streaming cubits: at least one test pushes an event via `RefreshBus.instance.push<T>(...)` and asserts the cubit reloaded
- [ ] `wait:` set when the cubit's `act` triggers `unawaited(...)` work that must settle before assertions
- [ ] Test passes locally with `flutter test <path>`
