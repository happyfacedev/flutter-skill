// Single project-wide ErrorRegistry subclass. One per project.
//
// Lives at:
//   lib/core/network/app_error_registry.dart
//
// Wire it into Dio exactly once at boot via ErrorMappingInterceptor (see
// reference.md → "Wiring ErrorMappingInterceptor at boot").

import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:simple_network_handler/simple_network_handler.dart';
import 'package:your_app/core/failures/generic_failure.dart';
import 'package:your_app/core/failures/no_internet_failure.dart';
import 'package:your_app/core/failures/timeout_failure.dart';
import 'package:your_app/core/failures/validation_failure.dart';
import 'package:your_app/features/<feature>/logic/apis/feature_api.dart';

class AppErrorRegistry extends ErrorRegistry {
  @override
  ErrorModelRegistry get endpointRegistry => {
        // Global error mappings — apply to every endpoint unless overridden.
        '*': {
          422: (json) => Left(ValidationFailure.fromJson(json)),
        },
        // Endpoint-specific mappings — override the global for one endpoint.
        FeatureApiPath.createItem: {
          403: (json) => Left(ForbiddenFailure.fromJson(json)),
          409: (json) => Left(ConflictFailure.fromJson(json)),
        },
        // Treat-error-as-success — non-2xx status returned as Right(...)
        // when the failure is actually the desired outcome.
        // AuthApiPath.logout: {
        //   401: (json) => const Right(null),
        // },
      };

  // Transport-layer errors (no HTTP response was received).
  @override
  DioErrorRegistry get dioRegistry => {
        DioExceptionType.connectionError: const NoInternetFailure(),
        DioExceptionType.connectionTimeout: const TimeoutFailure(),
        DioExceptionType.receiveTimeout: const TimeoutFailure(),
      };

  // Catch-all for anything not matched above.
  @override
  Failure get genericError => const GenericFailure();
}
