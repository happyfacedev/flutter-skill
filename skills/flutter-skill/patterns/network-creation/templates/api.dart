// Retrofit API client + co-located ApiPath constants.
//
// Lives at:
//   lib/features/<feature>/logic/apis/<feature>_api.dart
//
// Two rules to remember:
//   1. ApiPath class lives in the same file as the API — they refactor together
//      and the registry's endpoint-specific entries reference these constants.
//   2. @lazySingleton — stateless transport adapter, one lazy instance app-wide.

import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:retrofit/retrofit.dart';
import 'package:your_app/features/<feature>/logic/models/request_bodies/create_item_request_body.dart';
import 'package:your_app/features/<feature>/logic/models/responses/item_response.dart';
import 'package:your_app/features/<feature>/logic/models/responses/items_response.dart';

part 'feature_api.g.dart';

class FeatureApiPath {
  static const String getItems = '/api/feature/items';
  static const String getItemById = '/api/feature/items/{id}';
  static const String createItem = '/api/feature/items';
}

@RestApi()
@lazySingleton
abstract class FeatureApi {
  // If your project uses named Dio clients, add @Named('mainDio') / @Named('authDio')
  // to the dio parameter. If it has only one Dio, drop @Named entirely.
  @factoryMethod
  factory FeatureApi(Dio dio) = _FeatureApi;

  @GET(FeatureApiPath.getItems)
  Future<ItemsResponse> getItems();

  @GET(FeatureApiPath.getItemById)
  Future<ItemResponse> getItemById({
    @Path('id') required int id,
  });

  @POST(FeatureApiPath.createItem)
  Future<ItemResponse> createItem({
    @Body() required CreateItemRequestBody requestBody,
  });
}
