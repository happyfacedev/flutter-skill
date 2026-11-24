# Form Creation — Reference

Lookup index for `lib/core/widgets/form_inputs/` and the `formz` API as used here.

## Existing inputs — search before creating

Source: `lib/core/widgets/form_inputs/`.

| Class | Type signature | Notes |
|---|---|---|
| `Email` | `FormzInput<String, EmailValidationError>` | Errors: `empty`, `invalid`. Trims via cubit before `.dirty(value)`. |
| `Password` | `ManualErrorFormzInput<String, List<PasswordValidationError>>` | Errors: `empty`, `incorrectPassword`. Use `.withError(value, error)` for server errors. Login flavor — minimal client-side validation. |
| `RegisterPassword` | `FormzInput<String, List<RegisterPasswordValidationError>>` | Errors: `empty`, `min8Chars`, `min1Digit`, `min1SpecialChar`, `min1UppercaseChar`. Used for sign-up where strong rules apply. |
| `ConfirmPassword` | `FormzInput<String, ConfirmPasswordValidationError>` | Errors: `empty`, `invalid`. Takes `required this.password` in both `.pure()` and `.dirty()` constructors for cross-field comparison. |
| `TextFormInput` | `FormzInput<String, TextValidationError>` | Errors: `empty`. Generic required text. |
| `Name` (`name.dart`) | `FormzInput<String, NameValidationError>` | First/last name input — see the file for current error set. |
| `Phone` (`phone/`) | (subfolder) | Phone-specific input with country code handling. |

The barrel `form_inputs.dart` re-exports all of them — `import 'package:core_boilerplate/core/widgets/form_inputs/form_inputs.dart';`.

If your input semantically matches one of these, use it as-is. Adding a new input is justified when:
- The validation rules are distinct (e.g., a postal code regex, a username constraint)
- The accepted type isn't `String` (e.g., a `DateTime` input)
- The error enum needs new variants the existing ones don't have

## The `formz` API cheat sheet

`FormzInput<T, E>` exposes these getters consumers use:

| Getter | Meaning |
|---|---|
| `value` | The current raw value |
| `isPure` | True when constructed with `.pure(...)`, false after the first `.dirty(...)` |
| `isNotPure` | Inverse of `isPure` |
| `isValid` | True when `validator(value)` returned `null` |
| `isNotValid` | Inverse of `isValid` |
| `error` | The error returned by `validator(value)`, or `null` if valid |
| `displayError` | The error if `isPure == false`, else `null` — **the canonical "should I render the error" predicate in this project** |

Read `input.displayError` directly; don't hand-roll `isNotValid && !isPure` getters — same result, more code, drifts from upstream.

## `FormTextField` props

Source: `lib/core/widgets/form_text_field.dart`.

| Prop | Default | Notes |
|---|---|---|
| `controller` | `null` | Optional `TextEditingController`; bring one if you need to imperatively read/write the field |
| `validator` | `null` | `String? Function(String?)` — called on debounce. Return `null` for no error, the error string to display. Typically: `(_) => state.x.displayError?.errorMessage(context)` |
| `hintText` | `null` | Label text |
| `obscureText` | `false` | True for password fields |
| `keyboardType` | `TextInputType.text` | Use `.emailAddress`, `.number`, `.phone`, etc. for the right keyboard |
| `textInputAction` | `TextInputAction.next` | `.done` on the last field |
| `onChanged` | `null` | `void Function(String)` — wire to `context.read<Cubit>().xxxChanged` |
| `onFieldSubmitted` | `null` | Triggered on keyboard "next" / "done" |
| `leadingWidget` | `null` | Icon / widget at the field's start |
| `trailingWidget` | `null` | Icon / widget at the field's end (e.g., the eye toggle for password visibility) |
| `autocorrect` | `true` | False for emails, passwords, codes |
| `disabled` | `false` | Disables focus + editing |
| `focusNode` | `null` | Bring one when you need to programmatically focus / blur |
| `debounceDuration` | `Duration(milliseconds: 500)` | UI-level debounce for the error display. Set to `Duration.zero` for instant. |

The widget handles its own error animation via `FieldErrorWidget`. You do not wrap it in `Form` or `FormState` — there's no `formKey.currentState.validate()` flow here. Validation happens via the `FormzInput.isValid` getter in the cubit's state, and the visual error happens via the `validator` callback you pass.

## Cross-field validation pattern

`ConfirmPassword` is the canonical example. When the password changes, the confirm-password input needs to re-validate against the *new* password. The pattern:

```dart
class ConfirmPassword extends FormzInput<String, ConfirmPasswordValidationError> {
  const ConfirmPassword.pure({this.password = ''}) : super.pure('');
  const ConfirmPassword.dirty({required this.password, String value = ''})
      : super.dirty(value);

  final String password;   // <-- the other field's current value

  @override
  ConfirmPasswordValidationError? validator(String? value) {
    if (value == null || value.isEmpty) return ConfirmPasswordValidationError.empty;
    return value == password ? null : ConfirmPasswordValidationError.invalid;
  }
}
```

In the cubit, when the *primary* field changes, re-emit the dependent one too:

```dart
void passwordChanged(String value) {
  emit(state.copyWith(
    password: RegisterPassword.dirty(value),
    confirmPassword: ConfirmPassword.dirty(
      password: value,
      value: state.confirmPassword.value,
    ),
  ));
}
```

Both fields are recomputed, both validators run with the new context, and the page rebuilds whichever one has a changed error state (via `buildWhen` on the matching builder).

## Manual-error pattern (server errors back into a field)

For "incorrect password" on sign-in:

```dart
abstract class ManualErrorFormzInput<T, E> extends FormzInput<T, E> {
  final E? manualError;
  const ManualErrorFormzInput.dirty(super.value, [this.manualError]) : super.dirty();
  const ManualErrorFormzInput.pure(super.value, [this.manualError]) : super.pure();
  ManualErrorFormzInput.withError(super.value, this.manualError) : super.dirty();
}

class Password extends ManualErrorFormzInput<String, List<PasswordValidationError>> {
  const Password.pure() : super.pure('');
  const Password.dirty([super.value = '']) : super.dirty();
  Password.withError(String value, PasswordValidationError error)
      : super.withError(value, [error]);

  @override
  List<PasswordValidationError>? validator(String? value) {
    if (manualError != null) return manualError;  // <-- short-circuit
    return (value?.isEmpty ?? true) ? [PasswordValidationError.empty] : null;
  }
}
```

The cubit injects the error after a failed submit; the next user keystroke clears it (because `passwordChanged` emits a plain `.dirty(value)` with no manual error).

## Debouncing decision tree

Default is **no cubit-level debounce** — every keystroke emits a state change, and `FormTextField` handles its own visual debounce (500ms) before displaying errors.

Add cubit-level debounce when:
- Validation triggers an **async check** (uniqueness, availability)
- Validation logs **telemetry** per keystroke (per-keystroke telemetry on a fast typist will flood the analytics pipeline)
- The cubit emits at a rate that causes **measurable rebuilds** on dependent widgets (rare — `BlocBuilder` with `buildWhen` filters most of this away)

The project's debouncer is `Debouncer` in `lib/core/utils/debouncer.dart`. See `AuthFormCubit` for the canonical usage:

```dart
late final Debounceable<void, String> _debouncedEmailChanged;

AuthFormCubit(...) : super(...) {
  _debouncedEmailChanged = debounce(_emailChanged);
}

void emailChanged(String value) => _debouncedEmailChanged(value);

Future<void> _emailChanged(String value) async {
  emit(state.copyWith(email: Email.dirty(value.trim())));
}
```

The public `emailChanged` calls the debounced wrapper; the actual `_emailChanged` runs after the debounce window.
