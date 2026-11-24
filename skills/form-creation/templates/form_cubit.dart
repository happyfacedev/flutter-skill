// A form cubit + state — lives under lib/features/<feature>/logic/cubit/.
//
// This template covers a single-field "update postal code" form. For
// multi-field forms with cross-field validation see AuthFormCubit in
// lib/features/auth/logic/cubit/auth_form_cubit.dart.
//
// Three files (or three classes — the rule of thumb is one class per file):
//   1. update_postal_code_state.dart
//   2. update_postal_code_cubit.dart
//   3. The page that wires FormTextField + PrimaryButton — see /ui

// ─── update_postal_code_state.dart ──────────────────────────────────────────

import 'package:equatable/equatable.dart';
import 'package:core_boilerplate/core/utils/bloc_status.dart';
import 'package:core_boilerplate/core/widgets/form_inputs/form_inputs.dart';
import 'package:core_boilerplate/features/profile/logic/failures/profile_failure.dart';

class UpdatePostalCodeState extends Equatable {
  const UpdatePostalCodeState({
    this.postalCode = const PostalCode.pure(),
    this.status = BlocStatus.initial,
    this.failure,
  });

  final PostalCode postalCode;
  final BlocStatus status;
  final ProfileFailure? failure;

  // Error display needs no getter — the page reads postalCode.displayError.
  bool get isFormValid => postalCode.isValid;

  bool get isSubmitting => status == BlocStatus.loading;

  UpdatePostalCodeState copyWith({
    PostalCode? postalCode,
    BlocStatus? status,
    ProfileFailure? failure,
  }) =>
      UpdatePostalCodeState(
        postalCode: postalCode ?? this.postalCode,
        status: status ?? this.status,
        failure: failure, // allow clearing to null
      );

  @override
  List<Object?> get props => [postalCode, status, failure];
}

// ─── update_postal_code_cubit.dart ──────────────────────────────────────────

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:core_boilerplate/features/profile/logic/repositories/profile_repository.dart';
import 'package:injectable/injectable.dart';

@injectable
class UpdatePostalCodeCubit extends Cubit<UpdatePostalCodeState> {
  UpdatePostalCodeCubit(this._repository)
      : super(const UpdatePostalCodeState());

  final ProfileRepository _repository;

  /// Called from FormTextField.onChanged — emits a dirty input so
  /// validation runs and the error surfaces (once dirty).
  void postalCodeChanged(String value) {
    emit(state.copyWith(postalCode: PostalCode.dirty(value.trim())));
  }

  /// Both gates (Rule 3): validity AND re-entry — the form is still valid
  /// after a first accepted tap, so isFormValid alone never blocks a
  /// double-submit racing past the disabled button.
  Future<void> submit() async {
    if (!state.isFormValid || state.isSubmitting) return;

    emit(state.copyWith(status: BlocStatus.loading));
    final result = await _repository.updatePostalCode(state.postalCode.value);
    if (isClosed) return;

    result.fold(
      (failure) {
        emit(state.copyWith(status: BlocStatus.failure, failure: failure));
        // addError surfaces via AppBlocObserver → global snackbar.
        addError(failure, StackTrace.current);
      },
      (_) => emit(state.copyWith(status: BlocStatus.success)),
    );
  }
}

// ─── Page wiring (see /ui for the full page shape) ────────────────────
//
// Inside the page:
//
//   BlocBuilder<UpdatePostalCodeCubit, UpdatePostalCodeState>(
//     buildWhen: (p, c) => p.postalCode != c.postalCode,
//     builder: (context, state) => FormTextField(
//       hintText: 'Postal code',
//       keyboardType: TextInputType.number,
//       onChanged: context.read<UpdatePostalCodeCubit>().postalCodeChanged,
//       validator: (_) => state.postalCode.displayError?.errorMessage(context),
//     ),
//   ),
//
//   BlocBuilder<UpdatePostalCodeCubit, UpdatePostalCodeState>(
//     buildWhen: (p, c) =>
//         p.isFormValid != c.isFormValid || p.status != c.status,
//     builder: (context, state) => PrimaryButton(
//       label: l.profileSaveButton,
//       onPressed: state.isFormValid && !state.isSubmitting
//           ? context.read<UpdatePostalCodeCubit>().submit
//           : null,
//       isLoading: state.isSubmitting,
//       semanticsIdentifier: 'profile-postal-code-save',
//     ),
//   ),
