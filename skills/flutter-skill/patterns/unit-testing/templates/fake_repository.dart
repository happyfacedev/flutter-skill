// Template: in-memory FAKE of a reactive repository. Replace your_app / Thing.
//
// Use when a mock + StreamController is not enough: multi-consumer scenarios,
// write-through assertions across several cubits, or reuse in widget tests.
// The fake holds real state and drives a real subject — no stubbing needed.
// Lives in test/helpers/ (or test/fakes/), never in lib/.

import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:rxdart/rxdart.dart';
// Failure base: `simple_network_handler_supabase.dart` on Supabase projects.
import 'package:simple_network_handler/simple_network_handler.dart';
import 'package:your_app/core/things/repositories/things_repository.dart';

class FakeThingsRepository implements ThingsRepository {
  final BehaviorSubject<List<Thing>> _things = BehaviorSubject();

  /// Next result for loadThings(); tests set this to simulate failures.
  Either<Failure, Unit> loadResult = const Right(unit);

  /// What loadThings() pushes on success.
  List<Thing> seedOnLoad = const [];

  @override
  Stream<List<Thing>> watchThings() => _things.stream;

  @override
  Future<Either<Failure, Unit>> loadThings() async {
    return loadResult.fold(Left.new, (_) {
      _things.add(seedOnLoad);
      return const Right(unit);
    });
  }

  @override
  Future<Either<Failure, Unit>> updateThing(Thing updated) async {
    return loadResult.fold(Left.new, (_) {
      final current = _things.valueOrNull ?? const <Thing>[];
      _things.add([
        for (final t in current) t.id == updated.id ? updated : t,
      ]);
      return const Right(unit);
    });
  }

  /// Test hook: push directly, simulating another flow's write-through.
  void emitThings(List<Thing> value) => _things.add(value);

  Future<void> dispose() => _things.close();
}
