// Template: test/helpers/helpers.dart — the barrel every test file imports.
// Export only the helpers this project's suite actually has (workflow step 3):
//
//   mocks.dart    — one `class MockX extends Mock implements X {}` per doubled
//                   type, shared suite-wide (never redeclared per test file)
//   builders.dart — object mothers: named-param factories with defaults,
//                   e.g. `Thing buildThing({String id = 'thing-1', ...})`
//   result.dart   — expectSuccess/expectFailure (only if a test asserts on an
//                   Either directly — repository Impls, utilities)
//   fixtures.dart — fixture()/fixtureJson() loaders (repository-Impl mapping
//                   tests with JSON payloads under test/fixtures/)
//   fallbacks.dart— registerFallbacks() (only once a non-primitive any() exists)

// Export ONLY the files that exist — a literal copy of all four fails to
// compile when the suite didn't need result/fixtures. mocks + builders are
// near-universal; the other two are repository-Impl-test only.
export 'builders.dart';
export 'mocks.dart';
// export 'fixtures.dart';  // uncomment for repository-Impl mapping tests
// export 'result.dart';    // uncomment when a test asserts on an Either
