# Form Creation

Forms in this project are **three coordinated pieces**:

1. **`FormzInput<T, ErrorEnum>` subclasses** in `lib/core/widgets/form_inputs/` — each input type (Email, Password, Phone, …) is a small class encoding its own validator and error enum.
2. **A form cubit + state** in the feature's `logic/cubit/` — owns one `FormzInput` per field, exposes `xxxChanged` methods that emit `.dirty(value)`, and a `submit()` method that calls the repository when `state.isFormValid`.
3. **A page widget** using `FormTextField` (`lib/core/widgets/form_text_field.dart`) that takes the matching validator from each `FormzInput` and renders the error text inline.

The pieces are loosely coupled — the input doesn't know about the cubit, the cubit doesn't know about the page, and the page consults the input only for its validator function. Adding a new field is mostly "add an input class + a state field + a `xxxChanged` method + a `FormTextField` call site."

## Critical Rules (Never Break)

1. **Each input is its own `FormzInput<T, ErrorEnum>` class.** *Why:* validators are stable, reusable, and tested independently of any form. `Email` works in both `AuthFormCubit` and a future `InviteSomeoneCubit` because its validator doesn't know which form it's in. Putting validation logic in the cubit instead — `if (!_emailRegex.hasMatch(state.email))` — bakes input semantics into business logic and prevents reuse.

2. **Validation errors are enums, never strings — and their messages are localized at render time.** Each `FormzInput` declares an `XxxValidationError` enum + an `XxxValidationErrorX` extension with an `errorMessage(BuildContext context)` method resolving through `context.localization` (keys in every `.arb` file). *Why:* enums keep the failure modes exhaustive and testable without a widget tree; resolving the string in `build` keeps validation messages localized (the localization core rule applies to them like any user-facing text) and follows locale changes live — returning pre-built localized strings from validators is a known staleness bug (flutter#143729).

3. **The form cubit guards `submit()` with BOTH gates: `if (!state.isFormValid || state.isSubmitting) return;`** *Why:* the UI's submit button disables itself, but a fast double-tap can fire `submit` before the disabled state propagates — and after a first accepted tap the form is *still valid*, so the validity gate alone never blocks re-entry; the `isSubmitting` gate is cubit-creation Rule 1 applied to forms. `submit()` also needs `if (isClosed) return;` after its `await` (cubit-creation Rule 6) — navigating away mid-submit must not crash.

4. **Error display goes through formz's native `displayError`.** `input.displayError` returns the error only once the input is dirty — a pure (untouched) field shows nothing even though its validator fails. *Why:* showing an error before the user has typed anything is hostile UX, and formz ships this exact predicate; hand-rolled `shouldDisplay<Field>Error` getters (`isNotValid && !isPure`) re-implement it and drift.

5. **Cubit emits `.dirty(value)` on every change, NEVER `.pure(value)`.** *Why:* `.pure()` is the constructor for untouched fields (initial state). Once the user has interacted, the field is dirty forever — even if they delete back to empty. Re-emitting `.pure()` would hide the empty-required error after the user clears the field, which is wrong.

6. **For server-side errors injected back into a field, use `ManualErrorFormzInput`.** *Why:* a sign-in returns "incorrect password" — that's a field-level error, not a snackbar. The `ManualErrorFormzInput` base class lets you construct an input with a forced error (`Password.withError(value, PasswordValidationError.incorrectPassword)`) so the existing `FormTextField` displays it through the same path as client-side validation errors. See `lib/core/widgets/form_inputs/formz_manual_error_extension.dart` and `Password` for the pattern.

## Decision: which `FormzInput` shape

| Validator returns | Use | Examples |
|---|---|---|
| `null` or `XxxValidationError` (single error) | Plain `FormzInput<String, XxxValidationError>` | `Email`, `TextFormInput`, `ConfirmPassword` |
| `null` or `List<XxxValidationError>` (multiple rules, want to surface each) | Plain `FormzInput<String, List<XxxValidationError>>` | `RegisterPassword` (must have ≥8 chars, ≥1 digit, ≥1 special, ≥1 uppercase) |
| Plus server-side error injection | Extend `ManualErrorFormzInput<T, E>` instead | `Password` for login (server may say "incorrect password") |
| Cross-field validation (depends on another field's current value) | Plain `FormzInput<String, XxxValidationError>` with a constructor parameter for the other field | `ConfirmPassword({required this.password, …})` |

The `errorMessage(context)` extension is what the page reads to render the error. For `List<E>` inputs, add a `combinedMessage(context)` extension on the list (see `Password` / `RegisterPassword`) that decides how to surface multiple errors (one-at-a-time, joined, or fully filtered to only-non-empty).

## Anatomy

### The input class

```dart
import 'package:formz/formz.dart';

enum EmailValidationError {
  empty,
  invalid,
}

extension EmailValidationErrorX on EmailValidationError {
  String errorMessage(BuildContext context) => switch (this) {
    EmailValidationError.empty => context.localization.emailRequired,
    EmailValidationError.invalid => context.localization.emailInvalid,
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

  // Form is submittable when every input is valid (including required-empty).
  // (Error display needs no getters — the page reads input.displayError.)
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
- `Equatable` for value equality (no Freezed — per the flutter-skill core rules)
- `BlocStatus` from `core/utils/bloc_status.dart` for submission tracking
- Error rendering reads `input.displayError` (native formz; `null` while pure)
- `isFormValid` as the canonical "enable submit" predicate
- `copyWith` is manual; `failure` is one-shot — direct assignment (`failure: failure`, as above), so any emit that omits it clears it. Never pass an explicit `null` (see cubit-creation Critical Rule 4)

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
    if (!state.isFormValid || state.isSubmitting) return; // both gates (Rule 3)

    emit(state.copyWith(status: BlocStatus.loading));
    final result = await _repository.signUp(
      email: state.email.value,
      password: state.password.value,
    );
    if (isClosed) return; // Rule 6 — no emit after close mid-submit

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
- `@injectable` (the core-rules default)
- One `xxxChanged` method per field, taking the raw `String` from the text-field's `onChanged`
- The `submit()` guards (`!isFormValid || isSubmitting`, plus `isClosed` after the await); calls the repository, folds the `Either<Failure, Success>` into state transitions
- `addError(failure, StackTrace.current)` for global error surfacing (per the error-handling core rule)

### Debouncing field changes

The default is **no debouncing** — every keystroke emits a state change. For most forms that's fine: validation is fast, the UI rebuilds the field that changed (via `BlocBuilder` with `buildWhen: (p, c) => p.email != c.email`), and the user sees errors as they type.

Debounce when validation has user cost — typically when:
- Validation triggers an async check (e.g., "is this username taken")
- Validation logs telemetry per keystroke
- The error message is jarring on every keystroke (e.g., showing "invalid email" while the user is still typing the address)

For the last case, see `AuthFormCubit` (`lib/features/auth/logic/cubit/auth_form_cubit.dart`) — it uses the `Debouncer` from `core/utils/debouncer.dart` to wait for a pause after the last keystroke before re-validating. Note that `FormTextField` *also* has internal debouncing for error display; the cubit-level debounce only matters when validation is genuinely costly.

**The debounce interval needs one referenceable source of truth.** When the cubit owns the duration, expose it as a public named constant (`static const debounce = Duration(...)`) and pass that to the `Debouncer`, so a test can `fakeAsync.elapse(TheCubit.debounce)`. When the duration is fixed inside a shared `Debouncer` util, don't add a second constant on the cubit (two values drift apart) — the test mirrors the util's value locally, citing its `file:line`. *Why:* a bare guessed duration in a test silently breaks when the real window changes.

### The page wiring

```dart
BlocBuilder<SignupFormCubit, SignupFormState>(
  buildWhen: (p, c) => p.email != c.email,
  builder: (context, state) => FormTextField(
    hintText: 'Email',
    keyboardType: TextInputType.emailAddress,
    onChanged: context.read<SignupFormCubit>().emailChanged,
    validator: (_) => state.email.displayError?.errorMessage(context),
  ),
),
```

Notes:
- `BlocBuilder` with `buildWhen` narrowed to *only* the field this widget renders
- `onChanged` goes through `context.read` (callback, not `build`)
- `validator` reads `displayError` (`null` while pure — nothing shows before the user types) and resolves the localized message with the page's `context`

For the submit button:

```dart
BlocBuilder<SignupFormCubit, SignupFormState>(
  buildWhen: (p, c) =>
      p.isFormValid != c.isFormValid || p.status != c.status,
  builder: (context, state) => PrimaryButton(
    label: l.signupSubmit,
    onPressed: state.isFormValid && !state.isSubmitting
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

- **Page-level structure** (Scaffold, BlocProvider, Semantics, theme tokens) → `/ui`
- **Cubit fundamentals** (`@injectable`, `Cubit<State>`, `BlocStatus`, `addError`) → `/cubit-creation`
- **The `FormTextField` widget itself** — it already exists; this skill teaches how to USE it, not how to rebuild it. If you need a different visual (pill input, underlined input), see `/ui` (`PillInput`, `UnderlineInput`).
- **Failure shape** (the `Failure` class, `getTitle`/`getSubtitle`) → `/failure-modeling`
- **The repository call** the form submits to → `/network-creation-supabase` (or `/network-creation` for REST projects)

## Templates

- [`templates/form_input.dart`](templates/form_input.dart) — a new `FormzInput` class with error enum + extension
- [`templates/form_cubit.dart`](templates/form_cubit.dart) — form cubit + state, single-field example with `submit()`

## Reference

See [reference.md](reference.md) for:
- The current input catalog in `lib/core/widgets/form_inputs/` (search before adding a new one)
- The `formz` API cheat sheet (`isValid`, `isNotValid`, `isPure`, `isNotPure`, `error`, `pureValue`, `value`)
- `FormTextField` props — what each does, when to set it
- The cross-field validation pattern (ConfirmPassword)
- The manual-error pattern (Password.withError, ManualErrorFormzInput)
- The debouncing decision tree

## Checklist

- [ ] Each form field is a `FormzInput` subclass in `lib/core/widgets/form_inputs/` (or already exists — searched first)
- [ ] Validation errors are an enum + `errorMessage(BuildContext)` extension resolving via `context.localization` — keys added to every `.arb` file (no hardcoded strings)
- [ ] Validator returns `null` on success, the error on failure (or `List<E>` for multi-rule inputs)
- [ ] For cross-field validation, the dependent input takes the other field's value via constructor (see `ConfirmPassword`)
- [ ] For server-side errors, the input extends `ManualErrorFormzInput` and has a `.withError(value, error)` constructor
- [ ] Form state extends `Equatable`, holds one `FormzInput` per field + `BlocStatus` + optional `failure`
- [ ] Error display reads `input.displayError` — no hand-rolled `shouldDisplay<Field>Error` getters
- [ ] State has `isFormValid` AND-ing every `input.isValid`
- [ ] State `copyWith` is manual (no Freezed); `failure` is direct-assigned (one-shot) — never `?? this.failure`, never explicit `null`
- [ ] Form cubit emits `.dirty(value)` on each change (never `.pure(value)`)
- [ ] `submit()` guards on `!state.isFormValid || state.isSubmitting` (Rule 3), has `if (isClosed) return;` after its `await`, and reports failures via `addError`
- [ ] Page wires each `FormTextField` with `buildWhen` narrowed to the field's `FormzInput`
- [ ] Submit button is disabled when `!state.isFormValid` or `state.isSubmitting`
- [ ] If validation cost is high (async or telemetry), cubit-level debouncing is added via `core/utils/debouncer.dart`
