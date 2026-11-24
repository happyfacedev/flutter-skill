# Failure Modeling — Reference

## Localization integration

`getTitle` and `getSubtitle` receive a `BuildContext`, so they can call into `context.localization`, the project-standard extension over Flutter's gen-l10n:

```dart
@override
String getTitle(BuildContext context) =>
    context.localization.featurePlanInactiveTitle;
```

Keep the non-localized `errorMessage` field as a fallback so failures stay `const` and unit-testable without pumping a widget tree.

## When a failure carries data

Most failures are zero-arg. A few need to transport server-supplied state to the UI:

- **Rate limiting** — `nextAvailableAt: DateTime` for the banner countdown
- **Quota exhaustion** — `attemptsRemaining: int` if the UI shows attempt count
- **Conflict resolution** — `serverVersion: int` for optimistic concurrency
- **Validation** — `fieldErrors: Map<String, String>` for inline form errors

Rule of thumb: if the UI would otherwise need to re-parse the payload or do a second round-trip to render the error, carry the data on the failure.

Pass via constructor, store as `final`, document in the doc-comment, and update the mapper to extract from `payload`.

## Equatable: yes or no?

Add `with EquatableMixin` if:
- You test cubits that emit failures (`bloc_test` `expect` matchers compare by equality)
- You compare failures in widget tests (`expect(state.failure, equals(SomeFailure()))`)

Skip if you only use failures as snackbar fodder. The base `Failure` class does not provide equality by default.

```dart
class FeatureNetworkFailure extends FeatureFailure with EquatableMixin {
  const FeatureNetworkFailure();
  @override
  List<Object?> get props => [code];
}
```

Note: if subclasses carry data (timestamps, IDs), include them in `props` or equality lies.

## Failures that should NOT auto-snackbar

Some projects route `Failure` instances through a global BlocObserver that shows a snackbar for every error. That's wrong for failures that represent business-expected states:

- Rate limits (UI shows an inline banner)
- "Form invalid" failures rendered next to the field
- Recoverable conflicts (UI shows a merge dialog)

Mark these in the class doc-comment so future readers don't wire them into the global error path. Cubits dispatch them via `emit` to a `failure` field on state instead of `addError`.

```dart
/// Rate-limit failure — NOT routed through the global error snackbar.
/// Surfaced as an inline banner via state. See cubit dispatch logic.
class FeatureRateLimitedFailure extends FeatureFailure { ... }
```

## Complex payload extraction

Real backends return messy payloads — fields may be missing, wrongly-typed, or coerced. The mapper should never throw. Defensive extraction:

```dart
FeatureFailure mapFeatureErrorCode(
  String code, {
  Map<String, dynamic>? payload,
}) {
  switch (code) {
    case 'CANCEL_DEADLINE_PASSED':
      // payload may carry `deadline` — but only if backend version >= X.
      final raw = payload?['deadline'];
      final deadline = raw is String ? DateTime.tryParse(raw) : null;
      if (deadline == null) return const FeatureUnknownFailure();
      return FeatureCancelDeadlinePassedFailure(deadline: deadline);

    case 'RATE_LIMITED':
      final nextAt = payload?['next_available_at'];
      // Treat missing data as a malformed response, not a crash.
      if (nextAt is! String) return const FeatureUnknownFailure();
      final parsed = DateTime.tryParse(nextAt);
      if (parsed == null) return const FeatureUnknownFailure();
      return FeatureRateLimitedFailure(nextAvailableAt: parsed);

    default:
      return const FeatureUnknownFailure();
  }
}
```

Rule of thumb: if the field is required and missing, fall back to the unknown variant. Don't `as String` blindly — `is String` first, `tryParse` second.

## Multi-RPC mappers

Sometimes the same code string means different things on different RPCs. E.g. `'NOT_FOUND'` on `getThing` is "missing thing" but `'NOT_FOUND'` on `undoAction` is "already undone." Parameterize the mapper:

```dart
enum FeatureRpc { fetchThing, doThing, undoThing }

FeatureFailure mapFeatureErrorCode(
  String code, {
  Map<String, dynamic>? payload,
  FeatureRpc rpc = FeatureRpc.fetchThing,
}) {
  if (rpc == FeatureRpc.undoThing && code == 'NOT_FOUND') {
    return const FeatureAlreadyUndoneFailure();
  }
  switch (code) {
    case 'NOT_FOUND':
      return const FeatureNotFoundFailure();
    // ... usual cases
    default:
      return const FeatureUnknownFailure();
  }
}
```

Use only when you have actual collisions. For non-colliding codes, the rpc parameter is dead weight — skip it.

## Common mistakes

| ❌ Don't | ✅ Do |
|----------|-------|
| `throw FeatureFailure()` from a repository | Return `Left(FeatureFailure())` |
| `Either<Exception, T>` | `Either<Failure, T>` |
| Localize at construction: `FeatureFailure(errorMessage: context.localization.x)` | Localize in `getTitle(context)`; keep constructor `const` |
| `String? getSubtitle(BuildContext context) => null` | Return `''` or the code — never `null` |
| `FeatureFailure(code: code)` with arbitrary strings | Concrete subclass per known code + fallback `FeatureUnknownFailure` |
| Map codes inside the cubit | `mapFeatureErrorCode(code)` lives next to the failure file |
| Catch `PostgrestException` / `DioException` in the repo to build a failure | Let the transport handler + registry do it |

## File layout

```
lib/
├── core/
│   └── failures/
│       └── generic_failure.dart        # Single catch-all (one per project)
└── features/
    └── <feature>/
        └── logic/
            └── failures/
                └── <feature>_failure.dart  # Abstract base + concretes + mapper
```

One file per feature failure hierarchy. The mapper function lives in the same file as the failures it produces — readers find both together.
