// OfflineFailure + the shared transport predicate — ONE file, one source of
// truth for "is this error connectivity?". The registry override and every
// raw try/catch site (Contract B, Edge Functions) both use it; a locally
// re-derived check is a forked source of truth that drifts.
//
// Lives at:
//   lib/core/failures/offline_failure.dart

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
// REST/Dio projects import 'package:simple_network_handler/simple_network_handler.dart'.
import 'package:simple_network_handler/simple_network_handler_supabase.dart';

/// App-wide connectivity failure (offline / timeout / host unreachable).
/// The `TransportFailure` mixin marks it so repositories pass it through
/// unchanged (`mapBusiness`) and observers can special-case connectivity once.
class OfflineFailure extends Failure with TransportFailure {
  const OfflineFailure();

  // Replace with `context.localization.offlineTitle` / `offlineSubtitle` —
  // ARB keys ship in the same commit (failure-modeling Critical rule 6).
  @override
  String getTitle(BuildContext context) => 'No internet connection';

  @override
  String getSubtitle(BuildContext context) =>
      'Check your connection and try again.';
}

/// Shared transport predicate. The `is SocketException` test matters:
/// `package:http`'s private `_ClientSocketException` only *implements*
/// SocketException, so the package registry's runtimeType name-match
/// (web-safe, but name-only) misses it — an `is` test does not.
bool isTransportError(Object error) =>
    error is TimeoutException || error is SocketException;
