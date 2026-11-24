// Mocktail fallback registrations a test suite typically needs.
//
// Call inside `setUpAll(() { ... })` at the top of `main()` BEFORE any
// `when(() => mock.method(any(...)))` that uses a non-primitive type.
// Without this, mocktail throws "A test tried to use any() ..." at setup.
//
// One-time per test file — typically grouped near the top.

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:your_app/core/failures/generic_failure.dart';

void registerProjectFallbacks() {
  // Either<L, R> — when stubbing `repo.foo()` to return `any<Either<...>>()`
  // (uncommon — usually you pass concrete Right/Left directly).
  // registerFallbackValue(const Right<Failure, void>(null));

  // Failure subclasses — when matching `verify(() => obs.onError(any()))` etc.
  // Project-wide: GenericFailure is always safe to register.
  registerFallbackValue(const GenericFailure());
  // Per-test: register any feature-specific failure your tests pass via `any()`.
  // Example (uncomment + import the real type):
  // registerFallbackValue(const OrganizationUnknownFailure());

  // Request bodies passed by `any(named: 'requestBody')`. Project-specific —
  // import the real request-body class and register a minimal instance.
  // registerFallbackValue(YourRequestBody(id: 'fallback'));

  // DateTime — when matching `any<DateTime>()`.
  registerFallbackValue(DateTime(2000));

  // StackTrace — when verifying `addError(any(), any())`.
  registerFallbackValue(StackTrace.empty);
}

// Usage in your test file:
//
// void main() {
//   setUpAll(registerProjectFallbacks);
//   // ... tests ...
// }
