// Repository impl — Contract A: error envelope.
//
// Use when your backend RPCs return HTTP 200 with `{error: 'CODE', ...}` on
// business failures. The transport layer sees success; you check
// `data['error']` inside the success branch and route through a code mapper.
//
// Lives at:
//   lib/features/<feature>/logic/repositories/<feature>_repository_impl.dart
//
// Three patterns shown:
//   1. RPC returning a single object — `fetchThing`
//   2. RPC with business error envelope — `doThing`
//   3. `.from()` table query returning a list — `listThings`

import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:simple_network_handler/simple_network_handler_supabase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:your_app/features/<feature>/logic/failures/<feature>_failure.dart';
import 'package:your_app/features/<feature>/logic/models/responses/feature_response.dart';
import 'package:your_app/features/<feature>/logic/repositories/<feature>_repository.dart';

@Injectable(as: FeatureRepository)
class FeatureRepositoryImpl implements FeatureRepository {
  FeatureRepositoryImpl(this._client);

  final SupabaseClient _client;

  // Helper for Postgres `date` params — Postgres rejects ISO 8601 datetimes
  // for `date` columns. Use only if this repo passes dates to such columns.
  String _dateParam(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  // 1. RPC returning a single object. No business envelope — transport-only.
  @override
  Future<Either<FeatureFailure, FeatureResponse>> fetchThing({
    required String id,
  }) async {
    final result = await SupabaseNetworkHandler.safeCall<Map<String, dynamic>>(
      () => _client.rpc('fetch_thing', params: {'p_id': id}),
    );
    return result.fold(
      (_) => const Left(FeatureNetworkFailure()),
      (data) => Right(FeatureResponse.fromJson(data)),
    );
  }

  // 2. RPC where backend may return `{error: 'CODE', ...}` with HTTP 200.
  //    The two-phase fold: transport-fail → network failure; success branch
  //    → check `data['error']` → route through mapper.
  @override
  Future<Either<FeatureFailure, FeatureResponse>> doThing({
    required String thingId,
    required String input,
  }) async {
    final result = await SupabaseNetworkHandler.safeCall<Map<String, dynamic>>(
      () => _client.rpc('do_thing', params: {
        'p_thing_id': thingId,
        'p_input': input,
      }),
    );
    return result.fold(
      (_) => const Left(FeatureNetworkFailure()),
      (data) {
        final code = data['error'] as String?;
        if (code != null) {
          return Left(mapFeatureErrorCode(code, payload: data));
        }
        return Right(FeatureResponse.fromJson(data));
      },
    );
  }

  // 3. `.from()` table query — Postgrest errors are caught by the registry,
  //    success branch sees a List (empty if no rows — never null).
  @override
  Future<Either<FeatureFailure, List<FeatureResponse>>> listThings() async {
    final result = await SupabaseNetworkHandler.safeCall<List<dynamic>>(
      () => _client.from('things').select(),
    );
    return result.fold(
      (_) => const Left(FeatureNetworkFailure()),
      (rows) {
        final things = rows
            .map((row) => FeatureResponse.fromJson(row as Map<String, dynamic>))
            .toList();
        return Right(things);
      },
    );
  }
}
