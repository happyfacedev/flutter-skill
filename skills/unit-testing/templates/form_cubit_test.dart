// Template: form cubit test — formz inputs, debounced setters, submit flow.
// Replace your_app / Signup placeholders; recompute the helpers import depth.
// Add `fake_async` to dev_dependencies (pinned) — it arrives transitively via
// flutter_test but transitive deps aren't importable.
//
// Debounced setters NEVER use blocTest: the emit happens after the debounce
// hop and `wait:` with a guessed duration is forbidden. Shape: plain test() +
// fakeAsync + elapse(the source's named constant) + assert cubit.state.
// If the source exposes no named constant, see reference.md (cite the
// source file:line in a local const — better, expose the constant per
// form-creation). Submit paths use blocTest as usual; the guarded submit's
// isClosed test needs a valid precondition, which plain test() can't seed —
// use blocTest with seed:.
//
// MULTI-MODE form cubits (e.g. unified login/register): each mode is its
// own request-path unit — per-mode success/failure/addError coverage, each
// seeded from its own valid-state object mother; guards are mode-independent,
// test them once.

import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
// Failure base: `simple_network_handler_supabase.dart` on Supabase projects.
import 'package:simple_network_handler/simple_network_handler.dart';
import 'package:your_app/features/signup/logic/cubit/signup_form_cubit.dart';
import 'package:your_app/features/signup/logic/failures/signup_failure.dart';

import '../../../../helpers/helpers.dart'; // recompute ../ depth for your path

void main() {
  group('SignupFormCubit', () {
    late MockSignupRepository repository;

    setUp(() {
      repository = MockSignupRepository();
      when(() => repository.signUp(any(), any()))
          .thenAnswer((_) async => const Left(SignupFailure()));
    });

    SignupFormCubit buildCubit() => SignupFormCubit(repository);

    group('debounced setters', () {
      test('emailChanged emits the dirty input after the debounce window', () {
        fakeAsync((async) {
          final cubit = buildCubit();

          cubit.emailChanged('a@b.co');
          expect(cubit.state.email.isPure, isTrue); // not yet — debounced

          // Elapse the source's real window. If the cubit exposes no named
          // constant (duration lives in a shared util), use a local
          //   const _debounce = Duration(milliseconds: 300); // mirrors debouncer.dart:NN
          // — never a bare guessed number.
          async.elapse(SignupFormCubit.debounce);
          async.flushMicrotasks();

          expect(cubit.state.email.value, 'a@b.co');
          cubit.close();
        });
      });

      test('isClosed guard: close inside the debounce window — no emit', () {
        fakeAsync((async) {
          final cubit = buildCubit();

          cubit.emailChanged('a@b.co');
          cubit.close();
          async.elapse(SignupFormCubit.debounce);
          async.flushMicrotasks(); // must not throw StateError

          expect(cubit.state.email.isPure, isTrue);
        });
      });
    });

    group('submit', () {
      blocTest<SignupFormCubit, SignupFormState>(
        'invalid form: no emissions, no repository call',
        build: buildCubit,
        act: (cubit) => cubit.submit(),
        expect: () => const <SignupFormState>[],
        verify: (_) => verifyNever(() => repository.signUp(any(), any())),
      );

      // form-creation Rule 3's second gate — the form is still valid after
      // the first tap, so only isSubmitting blocks re-entry. Verify-only.
      blocTest<SignupFormCubit, SignupFormState>(
        're-entry guard: second submit mid-flight is a no-op',
        setUp: () => when(() => repository.signUp(any(), any()))
            .thenAnswer((_) async => const Right(unit)),
        build: buildCubit,
        seed: () => validSignupState(), // object mother: every input valid
        act: (cubit) async {
          unawaited(cubit.submit());
          await cubit.submit();
        },
        verify: (_) => verify(() => repository.signUp(any(), any())).called(1),
      );

      blocTest<SignupFormCubit, SignupFormState>(
        'failure emits failure state and reports via addError',
        build: buildCubit,
        seed: () => validSignupState(),
        act: (cubit) => cubit.submit(),
        errors: () => [isA<SignupFailure>()],
      );

      // A branch the UI handles in place (e.g. field-level server error)
      // suppresses global reporting — the empty list asserts NO addError:
      blocTest<SignupFormCubit, SignupFormState>(
        'handled branch does not report (errors empty)',
        setUp: () => when(() => repository.signUp(any(), any()))
            .thenAnswer((_) async => const Left(EmailTakenFailure())),
        build: buildCubit,
        seed: () => validSignupState(),
        act: (cubit) => cubit.submit(),
        errors: () => <Matcher>[],
      );

      // Guarded method + precondition: plain test() can't reach a valid
      // state (no emit access), so the isClosed test is blocTest + seed:.
      blocTest<SignupFormCubit, SignupFormState>(
        'isClosed guard: no emit after close mid-submit',
        build: buildCubit,
        seed: () => validSignupState(),
        act: (cubit) async {
          final completer = Completer<Either<Failure, Unit>>();
          when(() => repository.signUp(any(), any()))
              .thenAnswer((_) => completer.future);

          final future = cubit.submit();
          await cubit.close();
          completer.complete(const Left(SignupFailure()));
          await future; // must not throw, must not emit past loading
        },
        expect: () => [
          validSignupState().copyWith(status: BlocStatus.loading),
        ],
      );
    });
  });
}
