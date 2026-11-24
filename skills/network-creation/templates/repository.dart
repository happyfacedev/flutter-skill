// Repository — abstract interface (optional) + @LazySingleton implementation.
//
// Lives at:
//   lib/features/<feature>/logic/repositories/<feature>_repository.dart
//   lib/features/<feature>/logic/repositories/<feature>_repository_impl.dart
//
// Two shapes shown:
//   1. `@Generate` for simple passthrough (requires simple_repository_generator)
//   2. Manual `SimpleNetworkHandler.safeCall` for everything else
//
// Skip the abstract interface if you don't need test doubles or env-specific
// implementations — `@lazySingleton class FeatureRepository { ... }` is fine.

import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:simple_network_handler/simple_network_handler.dart';
import 'package:simple_repository_generator/generate.dart';
import 'package:your_app/features/<feature>/logic/apis/feature_api.dart';
import 'package:your_app/features/<feature>/logic/failures/feature_failure.dart';
import 'package:your_app/features/<feature>/logic/models/request_bodies/create_item_request_body.dart';
import 'package:your_app/features/<feature>/logic/models/responses/item_response.dart';
import 'package:your_app/features/<feature>/logic/models/responses/items_response.dart';

part 'feature_repository.gen.dart';

abstract class FeatureRepository {
  // @Generate writes the safeCall boilerplate for you — use for 1:1 passthroughs.
  @Generate(apiClient: FeatureApi)
  Future<Either<Failure, ItemsResponse>> getItems();

  @Generate(apiClient: FeatureApi)
  Future<Either<Failure, ItemResponse>> getItemById({required int id});

  // Manual implementation when the method does more than a single API call.
  Future<Either<Failure, ItemResponse>> createItem({
    required CreateItemRequestBody requestBody,
  });
}

@LazySingleton(as: FeatureRepository)
class FeatureRepositoryImpl extends FeatureRepository
    with FeatureRepositoryGenerated {
  FeatureRepositoryImpl(this.apiClient);

  @override
  final FeatureApi apiClient;

  @override
  Future<Either<Failure, ItemResponse>> createItem({
    required CreateItemRequestBody requestBody,
  }) async {
    return SimpleNetworkHandler.safeCall(
      () => apiClient.createItem(requestBody: requestBody),
    );
  }
}
