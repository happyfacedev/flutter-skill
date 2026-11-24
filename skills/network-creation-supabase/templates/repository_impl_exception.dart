// Repository impl — Contract B: exception-coded.
//
// Use when your backend RPCs raise `PostgrestException` with the business code
// in `e.message` (typically a Postgres `raise '<CODE>' using errcode = 'P0001'`
// inside a SQL function). The transport handler would route the exception
// through the registry and lose the code; intercept with a local `try/catch`
// and map `e.message` yourself.
//
// Don't nest this inside `safeCall` — pick one mechanism per method.
//
// Lives at:
//   lib/features/<feature>/logic/repositories/<feature>_repository_impl.dart
//
// Failure seam: still return the WIDE `Either<Failure, T>` (matching the
// envelope template and the repo→cubit→state seam). NOTE: because this raw
// try/catch bypasses `safeCall`, it does NOT get the registry's automatic
// transport (offline / timeout) classification the way `mapBusiness` on a
// `safeCall` result does. A dead socket lands in the bare `catch` below, so the
// STANDARD shape classifies transport explicitly as the FIRST thing in that
// catch (`if (isTransportError(e)) return const Left(OfflineFailure());`) —
// shown below — so offline renders "No internet connection" instead of the
// feature-generic fallback. `isTransportError` + `OfflineFailure` both live in
// `lib/core/failures/offline_failure.dart` (templates/offline_failure.dart).

import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:your_app/core/failures/offline_failure.dart';
import 'package:your_app/features/<feature>/logic/failures/<feature>_failure.dart';
import 'package:your_app/features/<feature>/logic/models/responses/feature_response.dart';
import 'package:your_app/features/<feature>/logic/repositories/<feature>_repository.dart';

@LazySingleton(as: FeatureRepository)
class FeatureRepositoryImpl implements FeatureRepository {
  FeatureRepositoryImpl(this._client);

  final SupabaseClient _client;

  @override
  Future<Either<Failure, FeatureResponse>> doThing({
    required String thingId,
    required String input,
  }) async {
    try {
      final res = await _client.rpc(
        'do_thing',
        params: {
          'p_thing_id': thingId,
          'p_input': input,
        },
      );
      if (res == null) return const Left(FeatureUnknownFailure());
      return Right(FeatureResponse.fromJson(res as Map<String, dynamic>));
    } on PostgrestException catch (e) {
      // Map by `e.message` for P0001 raises, or `e.code` for SQLSTATEs.
      // The mapper falls back to FeatureUnknownFailure for unknown codes.
      return Left(mapFeatureErrorCode(e.message));
    } catch (e) {
      // This raw try/catch bypasses safeCall, so transport (offline / timeout)
      // is NOT auto-classified. Classify it FIRST, before the generic
      // fallback, so a dead socket renders "No internet connection".
      if (isTransportError(e)) return const Left(OfflineFailure());
      // Anything else collapses to the feature fallback.
      return const Left(FeatureUnknownFailure());
    }
  }
}
