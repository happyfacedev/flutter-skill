// Test for a cubit that subscribes to refresh-bus events via the
// RefreshBusSubscriber mixin.
//
// Strategy: push events on the real `RefreshBus.instance` and assert the
// cubit reloaded. The mixin's subscription is auto-cancelled when the cubit
// closes — so `blocTest`'s cleanup (which calls `close()`) handles teardown.

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:simple_refresh_bus/simple_refresh_bus.dart';
import 'package:your_app/core/events/refresh_events.dart';
import 'package:your_app/core/utils/bloc_status.dart';
import 'package:your_app/features/<feature>/logic/cubit/<feature>_cubit.dart';
import 'package:your_app/features/<feature>/logic/cubit/<feature>_state.dart';
import 'package:your_app/features/<feature>/logic/repositories/<feature>_repository.dart';

class MockFeatureRepository extends Mock implements FeatureRepository {}

void main() {
  late MockFeatureRepository repository;

  setUp(() {
    repository = MockFeatureRepository();
    when(() => repository.fetchList()).thenAnswer((_) async => const Right([]));
  });

  group('FeatureListCubit (streaming)', () {
    blocTest<FeatureListCubit, FeatureListState>(
      'reloads when UserOrganizationsChanged is pushed on the bus',
      build: () => FeatureListCubit(repository),
      act: (cubit) async {
        RefreshBus.instance.push<UserOrganizationsChanged>(const UserOrganizationsChanged());
        // Let the unawaited(load()) settle before bloc_test inspects state.
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
      expect: () => [
        isA<FeatureListState>().having((s) => s.status, 'status', BlocStatus.loading),
        isA<FeatureListState>().having((s) => s.status, 'status', BlocStatus.success),
      ],
      verify: (_) {
        verify(() => repository.fetchList()).called(1);
      },
    );

    blocTest<FeatureListCubit, FeatureListState>(
      'does NOT reload when an event for a different organization arrives',
      build: () => FeatureListCubit(repository),
      act: (cubit) async {
        RefreshBus.instance.push<OrganizationChanged>(
          const OrganizationChanged(organizationId: 'other-org'),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
      expect: () => <FeatureListState>[],  // no state changes
      verify: (_) {
        verifyNever(() => repository.fetchList());
      },
    );
  });
}
