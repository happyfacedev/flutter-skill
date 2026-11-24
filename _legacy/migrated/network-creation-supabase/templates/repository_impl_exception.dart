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

import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:your_app/features/<feature>/logic/failures/<feature>_failure.dart';
import 'package:your_app/features/<feature>/logic/models/responses/feature_response.dart';
import 'package:your_app/features/<feature>/logic/repositories/<feature>_repository.dart';

@Injectable(as: FeatureRepository)
class FeatureRepositoryImpl implements FeatureRepository {
  FeatureRepositoryImpl(this._client);

  final SupabaseClient _client;

  @override
  Future<Either<FeatureFailure, FeatureResponse>> doThing({
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
    } catch (_) {
      // Genuine transport errors — anything not a PostgrestException collapses
      // to a generic network failure.
      return const Left(FeatureNetworkFailure());
    }
  }
}
