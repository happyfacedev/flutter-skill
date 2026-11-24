// Reactive repository — BehaviorSubject cache + watch/load/write-through.
//
// Lives at (promote per feature-isolation when shared across features):
//   lib/features/<feature>/logic/repositories/<feature>_repository.dart
//   or lib/core/<domain>/repositories/ when platform-tier.
//
// Replace `your_app` with the project package name; Supabase transport shown —
// swap safeCall for the REST variant on dio/retrofit projects.
//
// Failure seam: methods return the WIDE `Either<Failure, T>`; fold(Left.new, ...)
// propagates transport (OfflineFailure) and auth failures unchanged. Mapping is
// GUARDED — a malformed row returns Left, never throws (the Impl test asserts
// the never-throws contract; see /unit-testing).

import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:rxdart/rxdart.dart';
import 'package:simple_network_handler/simple_network_handler_supabase.dart';
import 'package:your_app/features/<feature>/logic/apis/things_api.dart';
import 'package:your_app/features/<feature>/logic/failures/things_failure.dart';
import 'package:your_app/features/<feature>/logic/models/responses/thing_response.dart';

@lazySingleton
class ThingsRepository {
  ThingsRepository(this._api);

  // Thin seam over the client (dumb Future<dynamic> methods) — the Impl's
  // tests mock THIS, never SupabaseClient (see /unit-testing doubles table).
  final ThingsApi _api;

  // Private subject — the cache and the notification channel in one.
  // Only THIS class may add to it (write-through rule).
  final BehaviorSubject<List<ThingResponse>> _things = BehaviorSubject();

  /// Data-only stream. Late subscribers immediately receive the cached value.
  Stream<List<ThingResponse>> watchThings() => _things.stream;

  /// Synchronous snapshot for callers that need the current value once.
  List<ThingResponse>? get currentThings => _things.valueOrNull;

  /// Fetch from the backend and push into the stream.
  /// Errors return on THIS path — they are never pushed into the stream.
  Future<Either<Failure, Unit>> loadThings() async {
    final result = await SupabaseNetworkHandler.safeCall<dynamic>(_api.getThings);
    return result.fold(Left.new, (data) {
      try {
        _things.add([
          for (final json in data as List<dynamic>)
            ThingResponse.fromJson(json as Map<String, dynamic>),
        ]);
        return const Right(unit);
      } catch (_) {
        return const Left(ThingsFetchFailure());
      }
    });
  }

  /// Write-through mutation: backend call, then push the updated value —
  /// every watching cubit updates without a re-fetch.
  Future<Either<Failure, Unit>> updateThing(ThingResponse updated) async {
    final result = await SupabaseNetworkHandler.safeCall<dynamic>(
      () => _api.updateThing(updated.toJson()),
    );
    return result.fold(Left.new, (row) {
      try {
        final fresh = ThingResponse.fromJson(row as Map<String, dynamic>);
        _things.add([
          for (final thing in _things.value)
            if (thing.id == fresh.id) fresh else thing,
        ]);
        return const Right(unit);
      } catch (_) {
        return const Left(ThingsFetchFailure());
      }
    });
  }

  @disposeMethod
  void dispose() => _things.close();
}
