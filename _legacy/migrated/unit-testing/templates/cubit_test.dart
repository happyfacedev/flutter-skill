// Standard cubit test — bloc_test + mocktail.
//
// Lives at: test/features/<feature>/logic/cubit/<feature>_cubit_test.dart
//
// One source file → one test file. Each `blocTest` covers one behavior:
// the happy path, each specific failure, edge cases.

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:your_app/core/utils/bloc_status.dart';
import 'package:your_app/features/<feature>/logic/cubit/<feature>_cubit.dart';
import 'package:your_app/features/<feature>/logic/cubit/<feature>_state.dart';
import 'package:your_app/features/<feature>/logic/failures/<feature>_failure.dart';
import 'package:your_app/features/<feature>/logic/models/responses/feature_response.dart';
import 'package:your_app/features/<feature>/logic/repositories/<feature>_repository.dart';

class MockFeatureRepository extends Mock implements FeatureRepository {}

void main() {
  // Register fallback values for any non-primitive types used with `any()`.
  // Without this, `when(() => repo.doThing(payload: any(named: 'payload')))`
  // throws at test setup. Skip if all your `when(...)` matchers use literals.
  // See templates/mocktail_setup.dart for the shared helper pattern.
  setUpAll(() {
    // Example: registerFallbackValue(const GenericFailure());
  });

  late MockFeatureRepository repository;

  setUp(() {
    repository = MockFeatureRepository();
  });

  group('FeatureCubit', () {
    blocTest<FeatureCubit, FeatureState>(
      'loads data successfully',
      setUp: () {
        when(() => repository.fetchThing()).thenAnswer(
          (_) async => const Right(FeatureResponse(id: '1', name: 'test')),
        );
      },
      build: () => FeatureCubit(repository),
      act: (cubit) => cubit.loadData(),
      expect: () => [
        isA<FeatureState>().having((s) => s.status, 'status', BlocStatus.loading),
        isA<FeatureState>()
            .having((s) => s.status, 'status', BlocStatus.success)
            .having((s) => s.data?.id, 'data.id', '1'),
      ],
      verify: (_) {
        verify(() => repository.fetchThing()).called(1);
      },
    );

    blocTest<FeatureCubit, FeatureState>(
      'emits failure when repository returns Left',
      setUp: () {
        when(() => repository.fetchThing()).thenAnswer(
          (_) async => const Left(FeatureNetworkFailure()),
        );
      },
      build: () => FeatureCubit(repository),
      act: (cubit) => cubit.loadData(),
      expect: () => [
        isA<FeatureState>().having((s) => s.status, 'status', BlocStatus.loading),
        isA<FeatureState>()
            .having((s) => s.status, 'status', BlocStatus.failure)
            .having((s) => s.error, 'error', isA<FeatureNetworkFailure>()),
      ],
      // errors: asserts that `addError(failure, ...)` was called — the global
      // observer would then snackbar the failure. Use when the cubit MUST
      // route the failure to AppBlocObserver.
      errors: () => [isA<FeatureNetworkFailure>()],
    );

    blocTest<FeatureCubit, FeatureState>(
      'emits a specific failure variant when repository returns it',
      setUp: () {
        when(() => repository.fetchThing()).thenAnswer(
          (_) async => const Left(FeatureNotAuthorizedFailure()),
        );
      },
      build: () => FeatureCubit(repository),
      act: (cubit) => cubit.loadData(),
      expect: () => [
        isA<FeatureState>().having((s) => s.status, 'status', BlocStatus.loading),
        isA<FeatureState>()
            .having((s) => s.error, 'error', isA<FeatureNotAuthorizedFailure>()),
      ],
    );
  });
}
