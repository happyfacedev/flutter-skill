// Producer cubit test — verifies the cubit pushes the right RefreshBus events.
//
// Pattern: subscribe to the bus via `RefreshBus.instance.onDataStream<T>()`
// inside `setUp`, collect events in a list, assert in `verify`. Cancel the
// subscription in `tearDown` so events from later tests don't leak into the
// captured list.
//
// `onDataStream<T>` is the singleton bus's stream API for test/external use —
// the `RefreshBusSubscriber` mixin's `onData<T>` is for cubits, not for tests.
//
// Lives at: test/features/<feature>/logic/cubit/<feature>_cubit_test.dart

import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:simple_refresh_bus/simple_refresh_bus.dart';
import 'package:your_app/core/events/refresh_events.dart';
import 'package:your_app/core/utils/bloc_status.dart';
import 'package:your_app/features/<feature>/logic/cubit/<feature>_cubit.dart';
import 'package:your_app/features/<feature>/logic/cubit/<feature>_state.dart';
import 'package:your_app/features/<feature>/logic/failures/<feature>_failure.dart';
import 'package:your_app/features/<feature>/logic/repositories/<feature>_repository.dart';

class MockFeatureRepository extends Mock implements FeatureRepository {}

void main() {
  late MockFeatureRepository repository;
  late List<FeatureThingChanged> capturedEvents;
  late StreamSubscription<FeatureThingChanged> eventSubscription;

  setUp(() {
    repository = MockFeatureRepository();
    capturedEvents = <FeatureThingChanged>[];
    // Note: `RefreshBus.instance` is process-wide. The subscription captures
    // ALL events of this type fired during the test, including ones from
    // anything else in the same isolate. `tearDown` ensures clean state
    // between tests.
    eventSubscription = RefreshBus.instance
        .onDataStream<FeatureThingChanged>()
        .listen(capturedEvents.add);
  });

  tearDown(() async {
    await eventSubscription.cancel();
  });

  group('FeatureMutationCubit', () {
    blocTest<FeatureMutationCubit, FeatureMutationState>(
      'pushes FeatureThingChanged on success',
      setUp: () {
        when(() => repository.doThing(thingId: 't-1')).thenAnswer(
          (_) async => const Right(unit),
        );
      },
      build: () => FeatureMutationCubit(repository),
      act: (cubit) => cubit.doThing(thingId: 't-1'),
      // `wait:` lets the broadcast stream drain before `verify` runs. The
      // push is synchronous but stream delivery is async — without `wait`,
      // `capturedEvents` is checked too early.
      wait: const Duration(milliseconds: 50),
      expect: () => [
        isA<FeatureMutationState>().having((s) => s.status, 'status', BlocStatus.loading),
        isA<FeatureMutationState>().having((s) => s.status, 'status', BlocStatus.success),
      ],
      verify: (_) {
        expect(capturedEvents, hasLength(1));
        expect(capturedEvents.single.thingId, equals('t-1'));
      },
    );

    blocTest<FeatureMutationCubit, FeatureMutationState>(
      'does NOT push event on failure',
      setUp: () {
        when(() => repository.doThing(thingId: 't-1')).thenAnswer(
          (_) async => const Left(FeatureNetworkFailure()),
        );
      },
      build: () => FeatureMutationCubit(repository),
      act: (cubit) => cubit.doThing(thingId: 't-1'),
      wait: const Duration(milliseconds: 50),
      expect: () => [
        isA<FeatureMutationState>().having((s) => s.status, 'status', BlocStatus.loading),
        isA<FeatureMutationState>().having((s) => s.status, 'status', BlocStatus.failure),
      ],
      errors: () => [isA<FeatureNetworkFailure>()],
      verify: (_) {
        expect(capturedEvents, isEmpty);
      },
    );
  });
}
