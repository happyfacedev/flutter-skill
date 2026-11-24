// Template: test/helpers/result.dart — THE ONLY test file that touches the
// result wrapper's API. Every test asserts through these helpers, so the
// dartz Either → sealed Result migration edits this file and nothing else.

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';

/// Extracts the success value or fails the test with the failure's details.
T expectSuccess<F, T>(Either<F, T> result) => result.fold(
      (failure) => fail('Expected success but got failure: $failure'),
      (value) => value,
    );

/// Extracts the failure or fails the test with the unexpected success value.
F expectFailure<F, T>(Either<F, T> result) => result.fold(
      (failure) => failure,
      (value) => fail('Expected failure but got success: $value'),
    );

// Usage in tests (never fold/isLeft/Left()/Right() in test bodies):
//   final things = expectSuccess(await repository.loadThings());
//   expect(things, hasLength(2));
//
//   final failure = expectFailure(await repository.loadThings());
//   expect(failure, isA<ThingsLoadFailure>());
//
// After the sealed-Result migration these bodies become an exhaustive switch:
//   T expectSuccess<T>(Result<T> result) => switch (result) {
//         Ok(:final value) => value,
//         Err(:final failure) => fail('Expected success but got: $failure'),
//       };
// Call sites do not change.
