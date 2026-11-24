// Template: StreamSubscriber cubit test (cubit that subscribes to a reactive
// repository stream IN ITS CONSTRUCTOR). Replace your_app / Thing /
// BlocStatus placeholders; recompute the helpers import depth.
//
// Most watching cubits are HYBRIDS: constructor subscription (stream
// reactions) PLUS request-path methods like load(). The two halves use
// different shapes IN THE SAME FILE — mixing is safe and expected:
//   stream reactions  → plain test(): controller.add → pumpEventQueue →
//                       assert cubit.state (blocTest's single-act model
//                       cannot drive constructor subscriptions)
//   request-path      → blocTest for transitions + errors: for addError
//   guards            → plain-test Completer form (below)
// Never use fakeAsync anywhere near this shape — rxdart #395.

import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
// Failure base: `simple_network_handler_supabase.dart` on Supabase projects.
import 'package:simple_network_handler/simple_network_handler.dart';
import 'package:your_app/core/things/cubit/things_cubit.dart';
import 'package:your_app/core/things/failures/things_failure.dart';

import '../../../helpers/helpers.dart'; // recompute ../ depth for your path

void main() {
  group('ThingsCubit (watching)', () {
    late MockThingsRepository repository;
    late StreamController<List<Thing>> thingsController;

    setUp(() {
      repository = MockThingsRepository();
      thingsController = StreamController<List<Thing>>.broadcast();
      // The stream stub MUST exist before the cubit is constructed —
      // the constructor subscribes immediately.
      when(() => repository.watchThings())
          .thenAnswer((_) => thingsController.stream);
      // Failure-default for the request path:
      when(() => repository.loadThings())
          .thenAnswer((_) async => const Left(ThingsLoadFailure()));
    });

    // Ordering: per-test addTearDown(cubit.close) runs BEFORE this group
    // tearDown, so the cubit (and its StreamSubscriber subscription) is
    // closed before the controller — the required order.
    tearDown(() async {
      await thingsController.close();
    });

    ThingsCubit buildCubit() => ThingsCubit(repository);

    // On a success stub for loadThings(), mirror the real Impl's
    // write-through: push into the controller BEFORE returning Right —
    // otherwise the cubit never leaves loading (data arrives via the
    // stream, not the return value):
    void stubLoadSuccess(List<Thing> things) {
      when(() => repository.loadThings()).thenAnswer((_) async {
        thingsController.add(things);
        return const Right(unit);
      });
    }

    group('stream reactions (plain test)', () {
      test('emits success with data when the repository pushes', () async {
        final cubit = buildCubit();
        addTearDown(cubit.close);

        thingsController.add([buildThing()]);
        await pumpEventQueue();

        expect(cubit.state.status, BlocStatus.success);
        expect(cubit.state.things, [buildThing()]);
      });

      test('every push updates state (write-through propagation)', () async {
        final cubit = buildCubit();
        addTearDown(cubit.close);

        thingsController.add([buildThing()]);
        await pumpEventQueue();
        thingsController.add([buildThing(), buildThing(id: 'thing-2')]);
        await pumpEventQueue();

        expect(cubit.state.things, hasLength(2));
        // NOTE: never thingsController.addError(...) — watch streams are
        // data-only by architecture; there is no error path to test here.
      });

      test('stops reacting after close (subscription cancelled)', () async {
        final cubit = buildCubit();
        await cubit.close();

        thingsController.add([buildThing()]);
        await pumpEventQueue();

        expect(cubit.state.things, isEmpty);
      });
    });

    group('load (request path — blocTest)', () {
      blocTest<ThingsCubit, ThingsState>(
        'emits [loading] then success arrives via the stream',
        setUp: () => stubLoadSuccess([buildThing()]),
        build: buildCubit,
        act: (cubit) => cubit.load(),
        expect: () => [
          const ThingsState(status: BlocStatus.loading),
          ThingsState(status: BlocStatus.success, things: [buildThing()]),
        ],
      );

      blocTest<ThingsCubit, ThingsState>(
        'emits [loading, failure] when load fails — stream untouched',
        build: buildCubit, // failure is the default stub
        act: (cubit) => cubit.load(),
        expect: () => [
          const ThingsState(status: BlocStatus.loading),
          const ThingsState(
            status: BlocStatus.failure,
            failure: ThingsLoadFailure(),
          ),
        ],
      );

      blocTest<ThingsCubit, ThingsState>(
        'reports the failure via addError',
        build: buildCubit,
        act: (cubit) => cubit.load(),
        errors: () => [isA<ThingsLoadFailure>()],
      );

      // One-shot contract across the halves: a fresh request clears a stale
      // failure left by a previous failed load (cubit-creation Rule 4 —
      // omission clears; seed: sets up the stale state directly).
      blocTest<ThingsCubit, ThingsState>(
        'a fresh load clears a stale one-shot failure',
        setUp: () => stubLoadSuccess([buildThing()]),
        build: buildCubit,
        seed: () => const ThingsState(
          status: BlocStatus.failure,
          failure: ThingsLoadFailure(),
        ),
        act: (cubit) => cubit.load(),
        expect: () => [
          const ThingsState(status: BlocStatus.loading), // omission cleared it
          ThingsState(status: BlocStatus.success, things: [buildThing()]),
        ],
      );

      // Guards in plain-test Completer form (loading guard only where
      // cubit-creation Rule 1 mandates one for this method):
      test('isClosed guard: no emit after close mid-load', () async {
        final completer = Completer<Either<Failure, Unit>>();
        when(() => repository.loadThings()).thenAnswer((_) => completer.future);

        final cubit = buildCubit();
        final future = cubit.load();
        await cubit.close();

        completer.complete(const Left(ThingsLoadFailure()));
        await future;
        expect(cubit.state.status, BlocStatus.loading);
      });
    });
  });
}
