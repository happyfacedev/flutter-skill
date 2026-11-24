// Template: request-path cubit test (cubit that calls repository methods).
// Replace your_app / Thing / <feature> / BlocStatus placeholders; recompute
// the helpers import depth for your file's actual location.
//
// Shape: failure is the DEFAULT stub (setUp); success is the per-test
// override (blocTest setUp:). One test per failure BRANCH the cubit takes.
// Guards last: loading-guard only where cubit-creation Rule 1 mandates one;
// isClosed for every method that emits after an await.

import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
// Failure base: `simple_network_handler_supabase.dart` on Supabase projects.
import 'package:simple_network_handler/simple_network_handler.dart';
import 'package:your_app/features/things/logic/cubit/things_cubit.dart';
import 'package:your_app/features/things/logic/failures/things_failure.dart';

import '../../../../helpers/helpers.dart'; // recompute ../ depth for your path

void main() {
  group('ThingsCubit', () {
    late MockThingsRepository repository;

    setUp(() {
      repository = MockThingsRepository();
      // FAILURE-DEFAULT: every method stubbed to its failure case here.
      // Success is overridden inside the tests that need it.
      when(() => repository.loadThings())
          .thenAnswer((_) async => const Left(ThingsLoadFailure()));
    });

    ThingsCubit buildCubit() => ThingsCubit(repository);

    test('initial state is idle with no things', () {
      expect(buildCubit().state, const ThingsState());
    });

    group('loadThings', () {
      blocTest<ThingsCubit, ThingsState>(
        'emits [loading, success] with things on success',
        setUp: () => when(() => repository.loadThings())
            .thenAnswer((_) async => Right([buildThing()])),
        build: buildCubit,
        act: (cubit) => cubit.loadThings(),
        expect: () => [
          const ThingsState(status: BlocStatus.loading),
          ThingsState(status: BlocStatus.success, things: [buildThing()]),
        ],
      );

      // One test per failure BRANCH. If the cubit branches on the subtype,
      // one test per subtype; a pass-through cubit (stores whatever Left it
      // gets) needs only this one representative — subtype classification
      // belongs to the repository-Impl test.
      blocTest<ThingsCubit, ThingsState>(
        'emits [loading, failure] with the failure when load fails',
        build: buildCubit, // failure is already the default stub
        act: (cubit) => cubit.loadThings(),
        expect: () => [
          const ThingsState(status: BlocStatus.loading),
          const ThingsState(
            status: BlocStatus.failure,
            error: ThingsLoadFailure(),
          ),
        ],
      );

      // Side effects in their own test (Critical Rule 2):
      blocTest<ThingsCubit, ThingsState>(
        'calls repository.loadThings once',
        setUp: () => when(() => repository.loadThings())
            .thenAnswer((_) async => const Right([])),
        build: buildCubit,
        act: (cubit) => cubit.loadThings(),
        verify: (_) => verify(() => repository.loadThings()).called(1),
      );

      // addError reporting in its own test (errors: is a third concern):
      blocTest<ThingsCubit, ThingsState>(
        'reports the failure via addError',
        build: buildCubit,
        act: (cubit) => cubit.loadThings(),
        errors: () => [isA<ThingsLoadFailure>()],
      );
    });

    group('guards', () {
      // Loading guard — ONLY where cubit-creation Rule 1 mandates one for
      // this method. VERIFY-ONLY: value-equal emissions de-duplicate, so an
      // expect: list cannot distinguish guarded from unguarded — the call
      // count is the behavior.
      blocTest<ThingsCubit, ThingsState>(
        'loading guard: concurrent second call is a no-op',
        setUp: () => when(() => repository.loadThings())
            .thenAnswer((_) async => const Right([])),
        build: buildCubit,
        act: (cubit) async {
          // Do NOT await the first call — the second must land mid-flight.
          unawaited(cubit.loadThings());
          await cubit.loadThings();
        },
        verify: (_) => verify(() => repository.loadThings()).called(1),
      );

      // isClosed guard — for EVERY method that emits after an await.
      // Complete the Completer with the branch that actually emits after the
      // await (here: failure — if the success branch is a no-op, Right would
      // never exercise the guard).
      test('isClosed guard: no emit after close mid-request', () async {
        final completer = Completer<Either<Failure, List<Thing>>>();
        when(() => repository.loadThings()).thenAnswer((_) => completer.future);

        final cubit = buildCubit();
        final future = cubit.loadThings();
        await cubit.close();

        completer.complete(const Left(ThingsLoadFailure()));
        // Must not throw StateError('Cannot emit new states after close')
        // and must not change state:
        await future;
        expect(cubit.state.status, BlocStatus.loading);
      });
    });
  });
}
