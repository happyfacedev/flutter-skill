# Auth Package

Location: `lib/core/auth/` (logic — cubits, repositories, models) + `lib/features/auth/ui/` (pages, widgets)

## Purpose

Handles user authentication using Supabase. Auth accounts are shared across the platform — a single account works across every organization the user belongs to.

## Key Concepts

**Account separation:**
- `auth.users` - Authentication identity (email, password, verification)
- `profiles` - User profile data (one per user globally)
- `organization_users` - Links users to organizations with roles

## Business Flows

### Authentication Phases

1. **Authentication** - User logs in or registers
2. **Organization Resolution** - App determines which organization (tenant) to use
3. **Onboarding** - If new to the organization, collect profile and link user

### Organization Resolution

- 0 organizations → Prompt the user to find / enter an organization
- 1 organization → Use that organization
- Multiple → User selects (with "save as default" option)

### Terms Acceptance

Users must accept both platform terms and organization-specific terms. The app checks term versions on login and prompts if acceptance is needed.

## Architecture Pattern

Auth forms use a **cubit-managed validation** pattern:

### State Structure

```dart
class LoginState extends Equatable {
  final Email email;           // formz input
  final Password password;     // formz input
  final bool passwordVisible;
  final BlocStatus status;
  final AuthFailure? failure;

  // Computed validation properties
  bool get shouldDisplayEmailError => email.isNotValid && !email.isPure;
  bool get shouldDisplayPasswordError => password.isNotValid && !password.isPure;
  bool get isFormValid => email.isValid && password.isValid;
  bool get isSubmitting => status == BlocStatus.loading;
}
```

### Cubit Structure

```dart
class LoginCubit extends Cubit<LoginState> {
  // Debounced field handlers (300ms delay)
  late final Debounceable<void, String> _debouncedEmailChanged;
  late final Debounceable<void, String> _debouncedPasswordChanged;

  void emailChanged(String value) => _debouncedEmailChanged(value);
  void passwordChanged(String value) => _debouncedPasswordChanged(value);
  void togglePasswordVisibility() { ... }
  Future<void> submit() async { ... }
}
```

### Field Widget Pattern

```dart
class EmailField extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LoginCubit, LoginState>(
      buildWhen: (prev, curr) =>
          prev.email != curr.email || prev.status != curr.status,
      builder: (context, state) {
        return BaseTextField(
          onChanged: context.read<LoginCubit>().emailChanged,
          disabled: state.isSubmitting,
          hintText: 'Email',
          errorText: _getEmailError(state.email.error),
          shouldDisplayError: state.shouldDisplayEmailError,
        );
      },
    );
  }
}
```

### Key Principles

1. **No TextEditingController** - Fields read values from cubit state
2. **Debounced validation** - 300ms delay before showing errors
3. **Theme-aware colors** - Use `context.colors.hint` not hardcoded colors
4. **StatelessWidget forms** - No local state management needed

## Components

| Component | Purpose |
|-----------|---------|
| `AuthCubit` | Global auth state management |
| `LoginCubit` | Login form handling with debounced validation |
| `RegisterCubit` | Registration form handling with debounced validation |
| `EmailVerificationCubit` | Email verification resend |
| `AuthRepository` | Auth operations interface |

## Form Inputs (formz)

| Input | Validation |
|-------|------------|
| `Email` | Required, valid email format |
| `Password` | Required (login) |
| `RegisterPassword` | 8+ chars, 1 digit, 1 special char, 1 uppercase |
| `ConfirmPassword` | Must match password |

For complete auth flow documentation, see `/docs/mobile/auth/README.md`.