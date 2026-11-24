// Template: repository-Impl test — response→model mapping and error→Failure
// translation ARE the subject. Replace your_app / Things placeholders;
// recompute the helpers import depth. The registry FILE name varies per
// project (class and file name may differ) — find the project's real one.
//
// Supabase recipe: NEVER mock SupabaseClient (mocked Postgrest builders can't
// resolve to data — the success path is unreachable). Mock the feature's thin
// plain-Dart FeatureApi seam and drive the REAL safeCall + the app's error
// registry (setUpAll below), so error mapping runs exactly as in production.
// If the Impl still takes the raw client, extract the seam first — writing
// the Impl's test always satisfies network-creation-supabase's wrapper
// trigger — then rerun `dart run build_runner build --delete-conflicting-outputs`
// (the constructor change rewires DI). Seam methods return Future<dynamic> →
// the Impl uses safeCall<dynamic> + an explicit cast inside its guarded
// mapping block.
// REST (dio+retrofit) Impls follow the same shape with the retrofit API
// class mocked and DioException thrown.

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:your_app/core/network/app_supabase_error_registry.dart';
import 'package:your_app/features/things/logic/api/things_api.dart';
import 'package:your_app/features/things/logic/failures/things_failure.dart';
import 'package:your_app/features/things/logic/repositories/things_repository_impl.dart';

import '../../../../helpers/helpers.dart'; // recompute ../ depth for your path

// Seam placement: sibling of the repository (.../api/<feature>_api.dart),
// mirroring the feature's existing folder layout — core/-tier features
// without a logic/ layer follow the same sibling rule.

void main() {
  setUpAll(() {
    AppSupabaseErrorRegistry.initialize(); // real registry → real mapping
    // Only when a write method uses any() on a payload map — delete for
    // read-only APIs (an unused registration is noise):
    registerFallbackValue(<String, dynamic>{});
  });

  group('ThingsRepositoryImpl', () {
    late MockThingsApi api;
    late ThingsRepositoryImpl repository;

    setUp(() {
      api = MockThingsApi();
      repository = ThingsRepositoryImpl(api);
      // FAILURE-DEFAULT for a leaf client is the THROWN transport exception —
      // safeCall converts it (Rule 4's no-throwsA governs assertions, not
      // transport stubbing):
      when(() => api.fetchThings())
          .thenThrow(const PostgrestException(message: 'boom'));
    });

    // PLAIN-Impl shape: a value-returning fetch to assert mapping on.
    // A purely REACTIVE Impl has no such method (loadX returns Either<F,
    // Unit>; models are observable only via cache/stream) — assert its
    // response→model mapping in the write-through group below instead.
    group('fetchThings', () {
      test('maps backend rows to models (fixture, byte-identical JSON)',
          () async {
        when(() => api.fetchThings()).thenAnswer(
            (_) async => fixtureJson('things/things_rows.json'));

        final things = expectSuccess(await repository.fetchThings());

        expect(things, hasLength(2));
        expect(things.first, buildThing(id: 'thing-1'));
      });

      test('empty response maps to an empty list, not a failure', () async {
        when(() => api.fetchThings()).thenAnswer((_) async => <dynamic>[]);

        expect(expectSuccess(await repository.fetchThings()), isEmpty);
      });

      test('transport failure maps to ThingsFetchFailure', () async {
        // default stub already throws
        final failure = expectFailure(await repository.fetchThings());

        expect(failure, isA<ThingsFetchFailure>());
      });

      test('malformed row maps to ThingsFetchFailure — never throws', () async {
        when(() => api.fetchThings())
            .thenAnswer((_) async => <dynamic>[{'id': null}]);

        final failure = expectFailure(await repository.fetchThings());

        expect(failure, isA<ThingsFetchFailure>());
      });
    });

    group('updateThing', () {
      test('forwards id and payload to the API (side effect)', () async {
        when(() => api.updateThing(any(), any()))
            .thenAnswer((_) async => <String, dynamic>{});

        await repository.updateThing(buildThing(id: 'thing-9'));

        verify(() => api.updateThing('thing-9', any())).called(1);
      });

      test('void success — bare expectSuccess still fails on a Left', () async {
        when(() => api.updateThing(any(), any()))
            .thenAnswer((_) async => <String, dynamic>{});

        final result = await repository.updateThing(buildThing());

        expectSuccess(result); // Either<F, void>: call as a statement
      });
    });

    // REACTIVE Impls only (BehaviorSubject cache) — delete for plain Impls.
    // SUCCESS payloads land in the cache/stream — assert the push THERE.
    // FAILURES are still RETURNED (Either<F, Unit>) — per-branch failure
    // assertions stay on the returned value (the mapping group above).
    // Subscriptions cancel per test (addTearDown); repo closes in tearDown.
    group('write-through', () {
      // For a fully-reactive Impl, hoist this dispose to the OUTER group —
      // every constructed repo must be disposed, subscribed or not.
      tearDown(() => repository.dispose());

      test('success pushes mapped models into watchThings() and the cache',
          () async {
        when(() => api.fetchThings()).thenAnswer(
            (_) async => fixtureJson('things/things_rows.json'));
        final emissions = <List<Thing>>[];
        final sub = repository.watchThings().listen(emissions.add);
        addTearDown(sub.cancel);

        expectSuccess(await repository.loadThings());
        await pumpEventQueue();

        expect(emissions, hasLength(1));
        // Pure reactive Impls assert response→model mapping HERE —
        // field-level, on the first emission:
        expect(emissions.first.first, buildThing(id: 'thing-1'));
        expect(repository.currentThings, hasLength(2));
      });

      test('failure pushes NOTHING into the stream (data-only contract)',
          () async {
        final emissions = <List<Thing>>[];
        final sub = repository.watchThings().listen(emissions.add);
        addTearDown(sub.cancel);

        expectFailure(await repository.loadThings()); // default stub throws
        await pumpEventQueue();

        expect(emissions, isEmpty);
        expect(repository.currentThings, isNull);
      });

      // reactive-repository checklist: EVERY mapping site guarded — the
      // reactive shape must prove both halves of the guard at once.
      test('malformed row: Left returned AND nothing pushed', () async {
        when(() => api.fetchThings())
            .thenAnswer((_) async => <dynamic>[{'id': null}]);
        final emissions = <List<Thing>>[];
        final sub = repository.watchThings().listen(emissions.add);
        addTearDown(sub.cancel);

        final failure = expectFailure(await repository.loadThings());
        await pumpEventQueue();

        expect(failure, isA<ThingsFetchFailure>());
        expect(emissions, isEmpty); // no partial cache, no partial push
        expect(repository.currentThings, isNull);
      });
    });
  });
}
