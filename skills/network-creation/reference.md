# Network Creation (REST) — Reference

## Wiring `ErrorMappingInterceptor` at boot

The registry only works if Dio actually consults it. The intermediary is `ErrorMappingInterceptor` — add it once when the Dio instance is built (typically in a DI module). Multiple Dio instances (auth client, main client) each get their own interceptor referencing the same registry.

```dart
@module
abstract class DioModule {
  @injectable
  Dio dio(AppErrorRegistry registry) {
    final dio = Dio(BaseOptions(baseUrl: kBaseUrl));
    dio.interceptors.add(ErrorMappingInterceptor(registry));
    return dio;
  }
}
```

If your project uses `getIt` directly instead of a `@module`:

```dart
final registry = AppErrorRegistry();
final dio = Dio(BaseOptions(baseUrl: kBaseUrl))
  ..interceptors.add(ErrorMappingInterceptor(registry));
getIt.registerSingleton<Dio>(dio);
```

Either way, register **before** any API client is constructed.

## What the `@Generate` mixin generates

For an abstract method annotated `@Generate(apiClient: FeatureApi)`, the `build_runner` step produces a mixin like this in `feature_repository.gen.dart`:

```dart
mixin FeatureRepositoryGenerated on FeatureRepository {
  FeatureApi get apiClient;

  @override
  Future<Either<Failure, ItemsResponse>> getItems() {
    return SimpleNetworkHandler.safeCall(() => apiClient.getItems());
  }

  @override
  Future<Either<Failure, ItemResponse>> getItemById({required int id}) {
    return SimpleNetworkHandler.safeCall(() => apiClient.getItemById(id: id));
  }
}
```

That's why the impl writes `with FeatureRepositoryGenerated` — it picks up the boilerplate. The impl still implements anything **not** marked `@Generate` itself (manual methods, methods needing transformation).

## `@Generate` vs manual `safeCall`

`@Generate` (from `simple_repository_generator`, used via `build_runner`) generates a mixin that wraps each annotated method in `SimpleNetworkHandler.safeCall`. It saves writing the same try-pattern repeatedly.

```dart
abstract class FeatureRepository {
  @Generate(apiClient: FeatureApi)
  Future<Either<Failure, ItemsResponse>> getItems();
}

@Injectable(as: FeatureRepository)
class FeatureRepositoryImpl extends FeatureRepository
    with FeatureRepositoryGenerated {            // generated mixin
  FeatureRepositoryImpl(this.apiClient);
  @override
  final FeatureApi apiClient;
}
```

**Use `@Generate` when:**
- The repo method is a 1:1 passthrough to one API method
- Input and output types match (just `Either`-wrapped)
- No request transformation, response transformation, or chained calls

**Use manual `safeCall` when:**
- You combine multiple API calls into one repo operation
- The response needs reshaping before returning
- You need `onEndpointError` for logic the registry can't express
- Caching, retry, or other side effects wrap the call

Manual shape:

```dart
@override
Future<Either<Failure, ItemsResponse>> getItems() async {
  return SimpleNetworkHandler.safeCall(
    () => apiClient.getItems(),
  );
}
```

`onEndpointError` is rare — use it only for logic that genuinely can't fit in the registry (e.g. inspecting the request body to choose a failure variant). If you reach for it, leave a comment explaining why.

```dart
@override
Future<Either<Failure, ItemResponse>> createItem({
  required CreateItemRequestBody requestBody,
}) async {
  return SimpleNetworkHandler.safeCall(
    () => apiClient.createItem(requestBody: requestBody),
    onEndpointError: (error) {
      // Custom: a 409 here means duplicate by user-chosen slug, NOT by id.
      // The registry can't disambiguate without the requestBody context.
      if (error is DioException && error.response?.statusCode == 409) {
        return Left(DuplicateSlugFailure(slug: requestBody.slug));
      }
      return null;            // fall through to registry handling
    },
  );
}
```

## Retrofit annotations beyond `@Path` and `@Body`

| Annotation | Use for | Example |
|---|---|---|
| `@Path('id')` | URL placeholder | `@GET('/items/{id}') Future<X> getById({@Path('id') required int id});` |
| `@Query('q')` | Query string param | `@GET('/items') Future<X> search({@Query('q') required String q});` |
| `@Queries()` | Map of query params | `@GET('/items') Future<X> filter({@Queries() Map<String, dynamic> filters});` |
| `@Header('X-Foo')` | Custom header per call | `@GET('/items') Future<X> get({@Header('X-Foo') required String foo});` |
| `@Body()` | JSON request body | `@POST('/items') Future<X> create({@Body() required CreateBody body});` |
| `@FormData()` / `@Field()` | `multipart/form-data` | `@POST('/upload') Future<X> upload(@Part() File file);` |
| `@CancelRequest()` | Cancellation token | `@GET('/x') Future<X> get(@CancelRequest() CancelToken token);` |

## Pagination

Two common shapes — pick what your API uses, document it in the repo method.

```dart
// Limit/offset:
@GET(FeatureApiPath.items)
Future<ItemsResponse> getItems({
  @Query('limit') required int limit,
  @Query('offset') required int offset,
});

// Cursor:
@GET(FeatureApiPath.items)
Future<ItemsResponse> getItems({
  @Query('cursor') String? cursor,
  @Query('limit') int limit = 20,
});
```

The response model typically carries the next cursor / total count:

```dart
@freezed
abstract class ItemsResponse with _$ItemsResponse {
  const factory ItemsResponse({
    required List<ItemResponse> items,
    String? nextCursor,
    int? totalCount,
  }) = _ItemsResponse;
  factory ItemsResponse.fromJson(Map<String, dynamic> json) =>
      _$ItemsResponseFromJson(json);
}
```

## `ErrorRegistry` patterns

### Global mapping (`'*'`)

Catches a status code regardless of which endpoint produced it. Use for cross-cutting errors like 422 validation envelopes that come back from many endpoints in the same shape.

```dart
'*': {
  422: (json) => Left(ValidationFailure.fromJson(json)),
}
```

### Endpoint-specific mapping

Catches a status only on the named endpoint. Use when the same status means different things on different endpoints (a 403 on `createItem` is "no permission to create"; a 403 on `deleteItem` is "no permission to delete this specific item").

```dart
FeatureApiPath.createItem: {
  403: (json) => Left(ForbiddenFailure.fromJson(json)),
  409: (json) => Left(ConflictFailure.fromJson(json)),
}
```

### Treat error as success

Sometimes a non-2xx response is actually the desired outcome. Logging out a user when the server reports 401 ("you're already signed out") is a common case. Return `Right(...)` from the handler.

```dart
AuthApiPath.logout: {
  401: (json) => const Right(null),
}
```

### Transport errors via `dioRegistry`

Maps Dio's transport-level exception types (no HTTP response was received). Tunes timeouts and connection errors into typed failures.

```dart
@override
DioErrorRegistry get dioRegistry => {
  DioExceptionType.connectionError: const NoInternetFailure(),
  DioExceptionType.connectionTimeout: const TimeoutFailure(),
  DioExceptionType.receiveTimeout: const TimeoutFailure(),
};
```

Define these failure classes `with TransportFailure` (snh 1.3+) — e.g. `class NoInternetFailure extends Failure with TransportFailure` — so repositories pass them through unchanged via `mapBusiness` and offline renders one app-wide message (Critical rule 4, failure-modeling Rule 5).

### Catch-all

```dart
@override
Failure get genericError => const NetworkFailure();
```

## Should the abstract `FeatureRepository` interface be skipped?

The abstract interface pays off in three cases:
- **Test doubles** — fake implementations for cubit unit tests
- **Env-specific implementations** — e.g. an offline / mock impl in dev
- **Subset exposure** — the impl has internal helpers you don't want the rest of the app to see

If none of these apply, skip the abstraction and just write `@lazySingleton class FeatureRepository { ... }`. Don't add ceremony speculatively.

## Optional: named Dio clients (auth vs main)

Some projects use separate Dio instances for authentication endpoints (with their own interceptors, e.g. refresh-token logic) and general API calls. This is optional — most projects need only one Dio instance.

If you have multiple, distinguish them with `@Named`:

```dart
@RestApi()
@injectable
abstract class AuthApi {
  @factoryMethod
  factory AuthApi(@Named('authDio') Dio dio) = _AuthApi;
}

@RestApi()
@injectable
abstract class FeatureApi {
  @factoryMethod
  factory FeatureApi(@Named('mainDio') Dio dio) = _FeatureApi;
}
```

If your project sticks with one Dio, drop `@Named` entirely.

## Common mistakes

| ❌ Don't | ✅ Do |
|----------|-------|
| `@POST('/api/feature/items')` | `@POST(FeatureApiPath.createItem)` |
| `@singleton` on the API class | `@injectable` (factory) by default |
| `try { ... } catch (DioException e) { ... }` in repo | Let `ErrorMappingInterceptor` + registry handle it |
| Multiple `ErrorRegistry` instances | One project-wide registry, wired once |
| Endpoint-specific status handling inside the repo method | `endpointRegistry[FeatureApiPath.x]` in the registry |
| Forget to add `ErrorMappingInterceptor` to Dio | Always added in the DI module / boot wiring |
| `@Body() RequestBody requestBody` typed as `dynamic` | Typed Freezed request-body model |

## File layout

```
lib/
├── core/
│   ├── failures/
│   │   └── generic_failure.dart            # see failure-modeling
│   ├── network/
│   │   └── app_error_registry.dart
│   └── injection/
│       └── dio_module.dart                 # wires ErrorMappingInterceptor
└── features/
    └── <feature>/
        └── logic/
            ├── failures/
            │   └── <feature>_failure.dart  # see failure-modeling
            ├── models/
            │   ├── responses/
            │   └── request_bodies/
            ├── apis/
            │   └── <feature>_api.dart      # @RestApi + FeatureApiPath
            └── repositories/
                ├── <feature>_repository.dart      # abstract (optional)
                └── <feature>_repository_impl.dart # @Injectable impl
```
