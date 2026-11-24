// A new FormzInput class — lives under lib/core/widgets/form_inputs/<name>.dart.
//
// Before adding: search lib/core/widgets/form_inputs/ for an existing input
// with matching semantics. The barrel `form_inputs.dart` re-exports all of
// them. Add to that barrel after creating.
//
// This template shows a postal-code input — single error enum, single-error
// validator, errorMessage extension. For multi-error or cross-field or
// manual-error variants, see Password / ConfirmPassword / RegisterPassword
// for the patterns.

import 'package:flutter/widgets.dart';
import 'package:formz/formz.dart';
import 'package:your_app/core/localization/localization_extension.dart';

/// Validation errors for the [PostalCode] [FormzInput].
enum PostalCodeValidationError {
  empty,
  invalid,
}

extension PostalCodeValidationErrorX on PostalCodeValidationError {
  /// User-facing error message, resolved at render time so it follows the
  /// active locale (never hardcode English — add the keys to every .arb file).
  String errorMessage(BuildContext context) => switch (this) {
        PostalCodeValidationError.empty =>
          context.localization.postalCodeRequired,
        PostalCodeValidationError.invalid =>
          context.localization.postalCodeInvalid,
      };
}

/// {@template postal_code}
/// Form input for a postal-code value (6 digits).
/// {@endtemplate}
class PostalCode extends FormzInput<String, PostalCodeValidationError> {
  /// {@macro postal_code}
  const PostalCode.pure() : super.pure('');

  /// {@macro postal_code}
  const PostalCode.dirty([super.value = '']) : super.dirty();

  static final _regex = RegExp(r'^\d{6}$');

  @override
  PostalCodeValidationError? validator(String? value) {
    if (value == null || value.isEmpty) {
      return PostalCodeValidationError.empty;
    }
    return _regex.hasMatch(value)
        ? null
        : PostalCodeValidationError.invalid;
  }
}

// Then in lib/core/widgets/form_inputs/form_inputs.dart, add:
//
//   export 'postal_code.dart';
