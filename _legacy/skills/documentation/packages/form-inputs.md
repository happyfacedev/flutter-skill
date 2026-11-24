# Form Inputs Package

Location: `lib/core/widgets/form_inputs/`

## Purpose

Provides form field validation using the Formz library. Contains reusable input models for common field types with built-in validation rules.

## Key Concepts

- Input models wrap values with validation state
- Each model has `valid` and `pure` states
- `pure` = user hasn't interacted yet (don't show errors)
- `dirty` = user has typed (can show errors if invalid)
- Validation errors have user-facing messages via extensions

## Input Types

| Type | Purpose | Validation |
|------|---------|------------|
| `Email` | Email addresses | Required, valid email format |
| `Password` | Login password | Required only |
| `RegisterPassword` | Registration password | 8+ chars, 1 digit, 1 special char, 1 uppercase |
| `ConfirmPassword` | Password confirmation | Required, must match password |
| `Phone` | Phone numbers | Min/max length based on country |

## Usage Pattern

### In Cubit State

```dart
class LoginState extends Equatable {
  final Email email;
  final Password password;

  const LoginState({
    this.email = const Email.pure(),
    this.password = const Password.pure(),
  });

  // Show error only when dirty AND invalid
  bool get shouldDisplayEmailError => email.isNotValid && !email.isPure;
}
```

### In Cubit Methods

```dart
void emailChanged(String value) {
  final email = Email.dirty(value.trim());
  emit(state.copyWith(email: email));
}
```

### Getting Error Messages

```dart
String? _getEmailError(EmailValidationError? error) {
  if (error == null) return null;
  return error.errorMessage;  // Extension method
}

String? _getPasswordError(List<PasswordValidationError>? errors) {
  if (errors == null || errors.isEmpty) return null;
  return errors.combinedMessage;  // For multi-error types
}
```

## Error Message Extensions

Each validation error enum has an `errorMessage` extension:

```dart
extension EmailValidationErrorX on EmailValidationError {
  String get errorMessage {
    switch (this) {
      case EmailValidationError.empty:
        return 'Email is required';
      case EmailValidationError.invalid:
        return 'Please enter a valid email';
    }
  }
}
```

For list-based errors (like `RegisterPassword`), use `combinedMessage`:

```dart
extension RegisterPasswordValidationErrorListX on List<RegisterPasswordValidationError> {
  String get combinedMessage {
    // Returns: "Password must contain: at least 8 characters, 1 digit"
  }
}
```

## Country Picker

Includes a country picker dialog for phone input with international dialing codes. Phone validation uses country-specific min/max lengths.