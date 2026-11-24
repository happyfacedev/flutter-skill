// Single catch-all failure — use when the feature has one "things went wrong"
// surface and the UI does not branch on error kind.
//
// Lives at `lib/core/failures/generic_failure.dart`. One per project is
// usually enough.

import 'package:flutter/material.dart';
// Pick the import that matches your transport:
//   REST/Dio:  import 'package:simple_network_handler/simple_network_handler.dart';
//   Supabase:  import 'package:simple_network_handler/simple_network_handler_supabase.dart';
import 'package:simple_network_handler/simple_network_handler.dart';

/// Catch-all failure for network/transport errors that cannot be attributed
/// to a specific feature.
class GenericFailure extends Failure {
  const GenericFailure({
    this.code = 'generic_error',
    this.errorMessage = 'Something went wrong',
  });

  final String code;
  final String errorMessage;

  // Replace `errorMessage` with `context.localization.genericErrorTitle`
  // once the key is added. The non-localized fallback stays so the class
  // remains const-constructible and testable.
  @override
  String getTitle(BuildContext context) => errorMessage;

  @override
  String getSubtitle(BuildContext context) => code;
}
