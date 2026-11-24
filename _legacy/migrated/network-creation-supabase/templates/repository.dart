// Repository interface — abstract, returns Either<FeatureFailure, T>.
//
// Lives at:
//   lib/features/<feature>/logic/repositories/<feature>_repository.dart
//
// The interface is optional — skip it when there's only one implementation and
// no plan to swap. Keep it when you have test doubles, multiple env-specific
// implementations, or want to expose only a subset of operations to callers.

import 'package:dartz/dartz.dart';
// Pull Failure (and FeatureFailure subclass) from the failure-modeling skill.
import 'package:your_app/features/<feature>/logic/failures/<feature>_failure.dart';
import 'package:your_app/features/<feature>/logic/models/responses/feature_response.dart';

/// Abstract interface for <feature> data operations.
///
/// All operations return `Either<FeatureFailure, T>` for consistent error
/// handling. See `failure-modeling` skill for how failures are shaped.
abstract class FeatureRepository {
  /// Fetches a single thing by id.
  Future<Either<FeatureFailure, FeatureResponse>> fetchThing({
    required String id,
  });

  /// Performs an action that returns a business result. Surfaces backend
  /// codes (`THING_INVALID`, `RATE_LIMITED`, etc.) as typed failures.
  Future<Either<FeatureFailure, FeatureResponse>> doThing({
    required String thingId,
    required String input,
  });

  /// Returns a list of things. Used by the listing page.
  Future<Either<FeatureFailure, List<FeatureResponse>>> listThings();
}
