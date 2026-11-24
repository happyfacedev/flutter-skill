// Template: test/flutter_test_config.dart — auto-loaded by flutter_test for
// every test in the package. One-time global setup: shared fallback values,
// log noise suppression. Keep it minimal; no per-suite logic here.
//
// IF THIS FILE ALREADY EXISTS in the project: MERGE the registerFallbacks()
// call into the existing testExecutable — never replace the file; existing
// configs usually carry load-bearing setup (theme fallbacks, localization).
// If nothing needs a fallback yet, skip fallbacks.dart entirely — an empty
// registrar is lint noise; add it when the first non-primitive any() appears.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mocktail/mocktail.dart';

// test/helpers/fallbacks.dart — one registerFallbackValue per non-primitive
// type used with any()/captureAny() anywhere in the suite:
//
//   void registerFallbacks() {
//     registerFallbackValue(buildThing());
//     registerFallbackValue(const ThingsState());
//     registerFallbackValue(Uri());
//   }

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  registerFallbacks();

  // Silence expected log noise (e.g. the global BlocObserver's addError
  // reporting) so real failures stand out in test output:
  debugPrint = (String? message, {int? wrapWidth}) {};

  await testMain();
}
