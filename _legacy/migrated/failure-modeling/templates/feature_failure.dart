// Feature failure hierarchy — abstract base + concrete subclasses + mapper.
//
// Lives in the feature's logic layer:
//   lib/features/<feature>/logic/failures/<feature>_failure.dart
//
// Use this shape when the backend returns business error codes the UI cares
// about and renders different copy / different UI per code.

import 'package:flutter/material.dart';
// Pick the import that matches your transport:
//   REST/Dio:  import 'package:simple_network_handler/simple_network_handler.dart';
//   Supabase:  import 'package:simple_network_handler/simple_network_handler_supabase.dart';
import 'package:simple_network_handler/simple_network_handler.dart';

/// Base class for all <feature>-related failures.
///
/// Subclasses override `getTitle` to return localized, code-specific copy.
/// `getSubtitle` defaults to the code; override only when you need it
/// empty or with extra detail.
abstract class FeatureFailure extends Failure {
  const FeatureFailure({
    this.code = 'feature_error',
    this.errorMessage = 'A feature error occurred',
  });

  final String code;
  final String errorMessage;

  @override
  String getTitle(BuildContext context) => errorMessage;

  @override
  String getSubtitle(BuildContext context) => code;
}

/// Specific business failure — backend returns `'THING_INVALID'`.
///
/// ARB keys (REQUIRED, ship in the same commit — see SKILL.md Critical rule 6):
///   - `featureThingInvalidTitle`
///   - `featureThingInvalidSubtitle` (optional — only if subtitle says more than title)
class FeatureThingInvalidFailure extends FeatureFailure {
  const FeatureThingInvalidFailure({
    super.code = 'thing_invalid',
    super.errorMessage = 'The thing is invalid',
  });

  @override
  String getTitle(BuildContext context) =>
      context.localization.featureThingInvalidTitle;

  @override
  String getSubtitle(BuildContext context) =>
      context.localization.featureThingInvalidSubtitle;
}

/// Failure that carries data — UI renders the retry-after timestamp inline.
///
/// Documented as "do not auto-snackbar" because this is a business-expected
/// state shown via a banner, not an error toast. Cubit dispatch logic should
/// check `is FeatureRateLimitedFailure` and route accordingly.
///
/// ARB keys (REQUIRED — see SKILL.md Critical rule 6):
///   - `featureRateLimitedTitle`
///   - `featureRateLimitedSubtitle` (interpolated with `nextAvailableAt`)
class FeatureRateLimitedFailure extends FeatureFailure {
  const FeatureRateLimitedFailure({
    required this.nextAvailableAt,
    super.code = 'rate_limited',
    super.errorMessage = 'Rate limited',
  });

  final DateTime nextAvailableAt;

  @override
  String getTitle(BuildContext context) =>
      context.localization.featureRateLimitedTitle;
}

/// Catch-all for the feature: unknown business codes, malformed payloads,
/// AND transport-tier failures bubbled up by the registry all land here.
/// Exactly one per hierarchy — do not add a separate `FeatureNetworkFailure`
/// or name it after a specific action. See SKILL.md Critical rule 5.
///
/// ARB keys (REQUIRED — see SKILL.md Critical rule 6):
///   - `featureUnknownTitle`
class FeatureUnknownFailure extends FeatureFailure {
  const FeatureUnknownFailure({
    super.code = 'unknown',
    super.errorMessage = 'An unknown error occurred',
  });

  @override
  String getTitle(BuildContext context) =>
      context.localization.featureUnknownTitle;
}

/// Maps a backend `error` code string to a [FeatureFailure] variant.
/// Unknown codes fall back to [FeatureUnknownFailure].
///
/// Optional `payload` parameter lets you extract structured data (e.g. a
/// `next_available_at` timestamp) without parsing it at the call site.
FeatureFailure mapFeatureErrorCode(
  String code, {
  Map<String, dynamic>? payload,
}) {
  switch (code) {
    case 'THING_INVALID':
      return const FeatureThingInvalidFailure();
    case 'RATE_LIMITED':
      final nextAt = payload?['next_available_at'] as String?;
      if (nextAt == null) return const FeatureUnknownFailure();
      return FeatureRateLimitedFailure(
        nextAvailableAt: DateTime.parse(nextAt),
      );
    default:
      return const FeatureUnknownFailure();
  }
}
