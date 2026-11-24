// SupabaseErrorRegistry subclass — catches transport-layer errors from every
// Supabase call routed through SupabaseNetworkHandler.safeCall.
//
// Lives at:
//   lib/core/network/app_supabase_error_registry.dart
//
// Initialize once at app boot, AFTER `Supabase.initialize(...)`:
//
//   await Supabase.initialize(url: ..., anonKey: ...);
//   AppSupabaseErrorRegistry.initialize();
//
// After init, every `SupabaseNetworkHandler.safeCall(...)` consults this
// registry to convert `AuthException` / `PostgrestException` / generic errors
// into typed `Failure` subclasses.

import 'package:dartz/dartz.dart';
import 'package:simple_network_handler/simple_network_handler_supabase.dart';
// Pull in your project's failures — both the cross-feature ones in core/
// (GenericFailure, OfflineFailure, SessionExpiredFailure, etc.) and any
// auth-specific ones. The prefix avoids colliding with this class's own
// `isTransportError` method.
import 'package:your_app/core/failures/generic_failure.dart';
import 'package:your_app/core/failures/offline_failure.dart' as transport;
import 'package:your_app/features/auth/logic/failures/auth_failure.dart';

class AppSupabaseErrorRegistry extends SupabaseErrorRegistry {
  AppSupabaseErrorRegistry._();

  static final AppSupabaseErrorRegistry _instance = AppSupabaseErrorRegistry._();

  static AppSupabaseErrorRegistry get instance => _instance;

  /// Registers this registry with `SupabaseNetworkHandler`. Call once at boot,
  /// after `Supabase.initialize(...)`.
  static void initialize() {
    SupabaseNetworkHandler.setErrorRegistry(_instance);
  }

  /// String-coded auth errors from `AuthException.code`. These come back from
  /// Supabase Auth (go-true). Map only the codes your UI cares about — unknown
  /// codes fall through to `genericError`.
  @override
  SupabaseAuthErrorRegistry get authErrorRegistry => {
        'invalid_credentials': (e) => const InvalidCredentialsFailure(),
        'user_not_found': (e) => const UserNotFoundFailure(),
        'email_not_confirmed': (e) => const EmailNotConfirmedFailure(),
        'user_already_exists': (e) => const EmailAlreadyInUseFailure(),
        'weak_password': (e) => const WeakPasswordFailure(),
        'session_expired': (e) => const SessionExpiredFailure(),
      };

  /// HTTP-status-coded Postgrest errors — RLS denials, missing tables, etc.
  /// The callback returns an `Either` so you can choose to treat some status
  /// codes as success (rare but supported).
  @override
  SupabaseStatusCodeRegistry get postgrestStatusRegistry => {
        401: (error, message, statusCode) =>
            const Left(SessionExpiredFailure()),
        // 404s can come from non-auth tables (RLS denials, missing rows for
        // RPCs aliased through views). A neutral failure keeps the user-facing
        // message generic.
        404: (error, message, statusCode) =>
            const Left(GenericFailure(errorMessage: 'Resource not found')),
      };

  /// Transport classification (snh 1.3+): offline / timeout become
  /// OfflineFailure (see templates/offline_failure.dart), which repositories
  /// pass through unchanged via `mapBusiness` — connectivity renders one
  /// app-wide message.
  @override
  Failure get transportError => const transport.OfflineFailure();

  /// Delegates to the shared predicate in offline_failure.dart — the same one
  /// raw try/catch sites call — so detection has one source of truth. `super`
  /// keeps the package's name-based match as a safety net.
  @override
  bool isTransportError(Object error) =>
      super.isTransportError(error) || transport.isTransportError(error);

  /// Catch-all for anything not matched above (unknown PostgrestException
  /// codes, parse errors, etc. — transport is already classified above).
  @override
  Failure get genericError => const GenericFailure();
}
