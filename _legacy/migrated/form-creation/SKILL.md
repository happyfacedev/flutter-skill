---
name: form-creation
description: Creates form inputs using the `formz` package + form cubits + form-aware pages. Covers `FormzInput<T, ErrorEnum>` shape (`.pure()` / `.dirty()` constructors + `validator` override + `isValid`/`isNotValid`/`isPure` getters), validation-error enums with a `errorMessage` extension getter, complex multi-error validators returning `List<E>` (Password, RegisterPassword), cross-field validation (ConfirmPassword takes the other field's value via constructor), the `ManualErrorFormzInput` extension for server-side errors (e.g., "incorrect password" injected after a failed login), the form-cubit shape (per-field `xxxChanged` methods with optional debouncing, `submit()` guarded by `state.isFormValid`, `BlocStatus` for submission status), the form-state shape (manual `copyWith`, one field per `FormzInput`, `shouldDisplay<Field>Error` computed getters using `isNotValid && !isPure`, `isFormValid` computed by AND-ing all `input.isValid`), and the `BaseFormTextField` widget that accepts a `validator` and handles debounced error display. Use when adding any form input (email / password / phone / text / number), building a new login/register/edit form, integrating server errors back into form fields, or when the user mentions "form", "formz", "FormzInput", "validator", "form validation", "BaseFormTextField", "isFormValid", "isPure", "dirty input", "field error", "form cubit", "form state", or "submit button enabled". Page structure (Scaffold + BlocProvider) → /page-creation. Cubit basics → /cubit-creation. The visual text-field widget → already exists as BaseFormTextField; no new widget needed per input.
argument-hint: "[form-name]"
---

# Form Creation

Forms in this project are **three coordinated pieces**:

1. **`FormzInput<T, ErrorEnum>` subclasses** in `lib/core/widgets/form_inputs/` — each input type (Email, Password, Phone, …) is a small class encoding its own validator and error enum.
2. **A form cubit + state** in the feature's `logic/cubit/` — owns one `FormzInput` per field, exposes `xxxChanged` methods that emit `.dirty(value)`, and a `submit()` method that calls the repository when `state.isFormValid`.
3. **A page widget** using `BaseFormTextField` (`lib/core/widgets/base_form_text_field.dart`) that takes the matching validator from each `FormzInput` and renders the error text inline.

The pieces are loosely coupled — the input doesn't know about the cubit, the cubit doesn't know about the page, and the page consults the input only for its validator function. Adding a new field is mostly "add an input class + a state field + a `xxxChanged` method + a `BaseFormTextField` call site."

## Critical Rules (Never Break)

1. **Each input is its own `FormzInput<T, ErrorEnum>` class.** *Why:* validators are stable, reusable, and tested independently of any form. `Email` works in both `AuthFormCubit` and a future `InviteSomeoneCubit` because its validator doesn't know which form it's in. Putting validation logic in the cubit instead — `if (!_emailRegex.hasMatch(state.email))` — bakes input semantics into business logic and prevents reuse.

2. **Validation errors are enums, never strings.** Each `FormzInput` declares an `XxxValidationError` enum + an `XxxValidationErrorX` extension with an `errorMessage` getter. *Why:* enums make the set of failure modes exhaustive (switch coverage is checked), serializable for tests, and free of localization concerns at the validator level. The string mapping lives in the extension where it can later be swapped for a `BuildContext` lookup if/when these inputs need full i18n.

3. **The form cubit guards `submit()` with `state.isFormValid`.** *Why:* the UI's submit button disables itself when `!state.isFormValid`, but a fast double-tap can fire `submit` before the disabled state propagates. The guard is one line, defensive, and prevents the submission from racing past validation.

4. **Form state has `shouldDisplay<Field>Error` computed getters using `isNotValid && !isPure`.** *Why:* showing an error before the user has typed anything is hostile UX. A pure (untouched) input doesn't display its error even though the validator is failing. Once the user types, the input becomes dirty and errors surface. This is the same pattern formz documents — codify it once per state class.

5. **Cubit emits `.dirty(value)` on every change, NEVER `.pure(value)`.** *Why:* `.pure()` is the constructor for untouched fields (initial state). Once the user has interacted, the field is dirty forever — even if they delete back to empty. Re-emitting `.pure()` would hide the empty-required error after the user clears the field, which is wrong.

6. **For server-side errors injected back into a field, use `ManualErrorFormzInput`.** *Why:* a sign-in returns "incorrect password" — that's a field-level error, not a snackbar. The `ManualErrorFormzInput` base class lets you construct an input with a forced error (`Password.withError(value, PasswordValidationError.incorrectPassword)`) so the existing `BaseFormTextField` displays it through the same path as client-side validation errors. See `lib/core/widgets/form_inputs/formz_manual_error_extension.dart` and `Password` for the pattern.

## Decision: which `FormzInput` shape

| Validator returns | Use | Examples |
|---|---|---|
| `null` or `XxxValidationError` (single error) | Plain `FormzInput<String, XxxValidationError>` | `Email`, `TextFormInput`, `ConfirmPassword` |
| `null` or `List<XxxValidationError>` (multiple rules, want to surface each) | Plain `FormzInput<String, List<XxxValidationError>>` | `RegisterPassword` (must have ≥8 chars, ≥1 digit, ≥1 special, ≥1 uppercase) |
| Plus server-side error injection | Extend `ManualErrorFormzInput<T, E>` instead | `Password` for login (server may say "incorrect password") |
| Cross-field validation (depends on another field's current value) | Plain `FormzInput<String, XxxValidationError>` with a constructor parameter for the other field | `ConfirmPassword({required this.password, …})` |

The `errorMessage` extension is what the page reads to render the error. For `List<E>` inputs, add a `combinedMessage` extension on the list (see `Password` / `RegisterPassword`) that decides how to surface multiple errors (one-at-a-time, joined, or fully filtered to only-non-empty).

## Anatomy

### The input class

```dart
import 'package:formz/formz.dart';

enum EmailValidationError {
  empty,
  invalid,
}

extension EmailValidationErrorX on EmailValidationError {
  String get errorMessage => switch (this) {
    EmailValidationError.empty => 'Email is required',
    EmailValidationError.invalid => 'Please enter a valid email',
  };
}

class Email extends FormzInput<String, EmailValidationError> {
  const Email.pure() : super.pure('');
  const Email.dirty([super.value = '']) : super.dirty();

  static final _regex = RegExp(r'^[\w!#$%&’*+/=?^`{|}~-]+@[\w-]+(?:\.[\w-]+)*$');

  @override
  EmailValidationError? validator(String? value) {
    if (value == null || value.isEmpty) return EmailValidationError.empty;
    return _regex.hasMatch(value) ? null : EmailValidationError.invalid;
  }
}
```

Standard shape: `.pure()` and `.dirty()` constructors, a `validator` override returning `null` on success or the error on failure, and the error-message extension.

### The form state

```dart
class SignupFormState extends Equatable {
  const SignupFormState({
    this.email = const Email.pure(),
    this.password = const RegisterPassword.pure(),
    this.confirmPassword = const ConfirmPassword.pure(),
    this.status = BlocStatus.initial,
    this.failure,
  });

  final Email email;
  final RegisterPassword password;
  final ConfirmPassword confirmPassword;
  final BlocStatus status;
  final AuthFailure? failure;

  // The "should display" getters — empty pure inputs don't show errors.
  bool get shouldDisplayEmailError => email.isNotValid && !email.isPure;
  bool get shouldDisplayPasswordError => password.isNotValid && !password.isPure;
  bool get shouldDisplayConfirmPasswordError =>
      confirmPassword.isNotValid && !confirmPassword.isPure;

  // Form is submittable when every input is valid (including required-empty).
  bool get isFormValid =>
      email.isValid && password.isValid && confirmPassword.isValid;

  bool get isSubmitting => status == BlocStatus.loading;

  SignupFormState copyWith({
    Email? email,
    RegisterPassword? password,
    ConfirmPassword? confirmPassword,
    BlocStatus? status,
    AuthFailure? failure,
  }) => SignupFormState(
    email: email ?? this.email,
    password: password ?? this.password,
    confirmPassword: confirmPassword ?? this.confirmPassword,
    status: status ?? this.status,
    failure: failure,
  );

  @override
  List<Object?> get props => [email, password, confirmPassword, status, failure];
}
```

Standard shape:
- `Equatable` for value equality (no Freezed — see `core-architecture.md` policy)
- `BlocStatus` from `core/utils/bloc_status.dart` for submission tracking
- `shouldDisplay<Field>Error` getters as the canonical "render the error" predicate
- `isFormValid` as the canonical "enable submit" predicate
- `copyWith` is manual; `failure` is allowed to clear to null (the cubit can pass `failure: null` explicitly to clear)

### The form cubit

```dart
@injectable
class SignupFormCubit extends Cubit<SignupFormState> {
  SignupFormCubit(this._repository) : super(const SignupFormState());

  final AuthRepository _repository;

  void emailChanged(String value) {
    emit(state.copyWith(email: Email.dirty(value.trim())));
  }

  void passwordChanged(String value) {
    final pwd = RegisterPassword.dirty(value);
    // Cross-field — re-validate confirmPassword against the new password
    final confirm = ConfirmPassword.dirty(
      password: value,
      value: state.confirmPassword.value,
    );
    emit(state.copyWith(password: pwd, confirmPassword: confirm));
  }

  void confirmPasswordChanged(String value) {
    emit(state.copyWith(
      confirmPassword: ConfirmPassword.dirty(
        password: state.password.value,
        value: value,
      ),
    ));
  }

  Future<void> submit() async {
    if (!state.isFormValid) return;

    emit(state.copyWith(status: BlocStatus.loading));
    final result = await _repository.signUp(
      email: state.email.value,
      password: state.password.value,
    );

    result.fold(
      (failure) {
        emit(state.copyWith(status: BlocStatus.failure, failure: failure));
        addError(failure, StackTrace.current);
      },
      (_) => emit(state.copyWith(status: BlocStatus.success)),
    );
  }
}
```

Standard shape:
- `@injectable` (per `core-architecture.md`'s default)
- One `xxxChanged` method per field, taking the raw `String` from the text-field's `onChanged`
- The `submit()` guard with `isFormValid`; calls the repository, folds the `Either<Failure, Success>` into state transitions
- `addError(failure, StackTrace.current)` for global error surfacing (per `core-architecture.md`'s error-handling policy)

### Debouncing field changes

The default is **no debouncing** — every keystroke emits a state change. For most forms that's fine: validation is fast, the UI rebuilds the field that changed (via `BlocBuilder` with `buildWhen: (p, c) => p.email != c.email`), and the user sees errors as they type.

Debounce when validation has user cost — typically when:
- Validation triggers an async check (e.g., "is this username taken")
- Validation logs telemetry per keystroke
- The error message is jarring on every keystroke (e.g., showing "invalid email" while the user is still typing the address)

For the last case, see `AuthFormCubit` (`lib/features/auth/logic/cubit/auth_form_cubit.dart`) — it uses the `Debouncer` from `core/utils/debouncer.dart` to wait 500ms after the last keystroke before re-validating. Note that `BaseFormTextField` *also* has internal debouncing for error display; the cubit-level debounce only matters when validation is genuinely costly.

### The page wiring

```dart
BlocBuilder<SignupFormCubit, SignupFormState>(
  buildWhen: (p, c) => p.email != c.email,
  builder: (context, state) => BaseFormTextField(
    hintText: 'Email',
    keyboardType: TextInputType.emailAddress,
    onChanged: context.read<SignupFormCubit>().emailChanged,
    validator: (_) => state.shouldDisplayEmailError
        ? state.email.error?.errorMessage
        : null,
  ),
),
```

Notes:
- `BlocBuilder` with `buildWhen` narrowed to *only* the field this widget renders — see `/page-creation`
- `onChanged` goes through `context.read` (callback, not `build`)
- `validator` is a closure that consults `shouldDisplayEmailError` first (don't show until dirty) then translates the input's `.error` to a user-facing string

For the submit button:

```dart
BlocBuilder<SignupFormCubit, SignupFormState>(
  buildWhen: (p, c) =>
      p.isFormValid != c.isFormValid || p.status != c.status,
  builder: (context, state) => MainButton(
    text: l.signupSubmit,
    onTap: state.isFormValid && !state.isSubmitting
        ? context.read<SignupFormCubit>().submit
        : null,
    isLoading: state.isSubmitting,
    semanticsIdentifier: 'signup-submit',
  ),
),
```

The button is disabled (`onTap: null`) when the form is invalid OR a submission is in flight. `isSubmitting` is the state's computed getter, not a separate field.

## Server-side errors back into a field

When a sign-in fails with "incorrect password," surface it on the password field (not a snackbar). Use `ManualErrorFormzInput`:

```dart
// 1. The Password input extends ManualErrorFormzInput
class Password extends ManualErrorFormzInput<String, List<PasswordValidationError>> {
  const Password.pure() : super.pure('');
  const Password.dirty([super.value = '']) : super.dirty();
  Password.withError(String value, PasswordValidationError error)
      : super.withError(value, [error]);

  @override
  List<PasswordValidationError>? validator(String? value) {
    if (manualError != null) return manualError;
    return (value?.isEmpty ?? true) ? [PasswordValidationError.empty] : null;
  }
}

// 2. The cubit re-emits the password with the server error attached
result.fold(
  (failure) {
    if (failure is InvalidCredentialsFailure) {
      emit(state.copyWith(
        password: Password.withError(
          state.password.value,
          PasswordValidationError.incorrectPassword,
        ),
        status: BlocStatus.failure,
      ));
    } else {
      // Other failures route to the global snackbar
      emit(state.copyWith(status: BlocStatus.failure, failure: failure));
      addError(failure, StackTrace.current);
    }
  },
  (_) => /* ... */,
);
```

The next keystroke clears the manual error because the user's `passwordChanged` emits `Password.dirty(newValue)` (no manual error) — that's the right UX: server errors only persist while the input matches what was submitted.

## What this skill does NOT cover

- **Page-level structure** (Scaffold, BlocProvider, Semantics, theme tokens) → `/page-creation`
- **Cubit fundamentals** (`@injectable`, `Cubit<State>`, `BlocStatus`, `addError`) → `/cubit-creation`
- **The `BaseFormTextField` widget itself** — it already exists; this skill teaches how to USE it, not how to rebuild it. If you need a different visual (pill input, underlined input), see `/widget-creation` and the `Ds*` family.
- **Failure shape** (the `Failure` class, `getTitle`/`getSubtitle`) → `/failure-modeling`
- **The repository call** the form submits to → `/network-creation-supabase` (or `/network-creation` for REST projects)

## Templates

- [`templates/form_input.dart`](templates/form_input.dart) — a new `FormzInput` class with error enum + extension
- [`templates/form_cubit.dart`](templates/form_cubit.dart) — form cubit + state, single-field example with `submit()`

## Reference

See [reference.md](reference.md) for:
- The current input catalog in `lib/core/widgets/form_inputs/` (search before adding a new one)
- The `formz` API cheat sheet (`isValid`, `isNotValid`, `isPure`, `isNotPure`, `error`, `pureValue`, `value`)
- `BaseFormTextField` props — what each does, when to set it
- The cross-field validation pattern (ConfirmPassword)
- The manual-error pattern (Password.withError, ManualErrorFormzInput)
- The debouncing decision tree

## Checklist

- [ ] Each form field is a `FormzInput` subclass in `lib/core/widgets/form_inputs/` (or already exists — searched first)
- [ ] Validation errors are an enum + `errorMessage` extension (not bare strings)
- [ ] Validator returns `null` on success, the error on failure (or `List<E>` for multi-rule inputs)
- [ ] For cross-field validation, the dependent input takes the other field's value via constructor (see `ConfirmPassword`)
- [ ] For server-side errors, the input extends `ManualErrorFormzInput` and has a `.withError(value, error)` constructor
- [ ] Form state extends `Equatable`, holds one `FormzInput` per field + `BlocStatus` + optional `failure`
- [ ] State has `shouldDisplay<Field>Error` getters using `isNotValid && !isPure`
- [ ] State has `isFormValid` AND-ing every `input.isValid`
- [ ] State `copyWith` is manual (no Freezed) and allows clearing `failure` to null
- [ ] Form cubit emits `.dirty(value)` on each change (never `.pure(value)`)
- [ ] `submit()` guards on `state.isFormValid` and reports failures via `addError`
- [ ] Page wires each `BaseFormTextField` with `buildWhen` narrowed to the field's `FormzInput`
- [ ] Submit button is disabled when `!state.isFormValid` or `state.isSubmitting`
- [ ] If validation cost is high (async or telemetry), cubit-level debouncing is added via `core/utils/debouncer.dart`
