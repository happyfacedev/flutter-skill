# Network Creation — REST (Dio + Retrofit)

For projects on `dio` + `retrofit` + `simple_network_handler` (v1.3+). Supabase projects use the sibling `network-creation-supabase` skill — the two are mutually exclusive.

Failure modeling (the shape of `Failure` subclasses, `getTitle`/`getSubtitle`, code-to-failure mappers) lives in the `failure-modeling` skill. This skill assumes you already know the failure shape and focuses on the transport layer.

## The shape

```
Repository (abstract, optional)
   ↓
RepositoryImpl  ──→  FeatureApi (Retrofit @RestApi)
                    methods wrapped by SimpleNetworkHandler.safeCall
                    transport errors caught by ErrorMappingInterceptor → registry
```

Three pieces, each in its own file:

1. **`FeatureApi`** — Retrofit interface annotated `@RestApi()`. Paths come from a co-located `FeatureApiPath` class — never raw strings.
2. **`FeatureRepository`** — abstract (optional) + `@LazySingleton(as: FeatureRepository)` impl. Returns the wide seam `Either<Failure, T>` — never `Either<FeatureFailure, T>`, which blocks transport pass-through by type (failure-modeling Rule 5). Simple passthrough methods can use `@Generate(apiClient: FeatureApi)` from `simple_repository_generator` to skip the manual `safeCall` boilerplate.
3. **`AppErrorRegistry`** — single project-wide subclass of `ErrorRegistry`. Wired into Dio via `ErrorMappingInterceptor` at boot.

## Critical rules

1. **Never raw-string an endpoint path. Use `@GET(FeatureApiPath.getItems)`, not `@GET('/api/feature/items')`.** *Why:* the `FeatureApiPath` class is the one source of truth for endpoints — grep finds all uses, the registry's endpoint-specific entries reference the same constants, and a backend URL change touches one line instead of many.

    **Name each constant after the Retrofit method that uses it** — `getItems`, `getItemById`, `createItem`, `searchTests` — one constant per method, lowerCamelCase. *Why:* the registry reads `endpointRegistry[FeatureApiPath.createItem]` and the repo reads `apiClient.createItem(...)` — using the same name on both sides makes the link obvious. Resource-only names (`items`, `clinicLocation`) collide when two methods share a URL (`GET /items` and `POST /items`).

2. **Annotate API clients and repository impls with `@lazySingleton`.** *Why:* they're stateless transport adapters used app-wide — one lazily-created instance per app is the community-standard lifetime; re-instantiating per injection buys nothing. (`@singleton` — eager, app-start construction — still needs explicit approval.)

3. **Wrap every repository call in `SimpleNetworkHandler.safeCall<T>` OR use `@Generate`. Don't mix manual `try/catch` with the registry.** *Why:* both routes funnel errors through the registry. Local `try/catch` on `DioException` duplicates the registry's work and produces two sources of truth for "what failure does a 403 become?"

4. **One `ErrorRegistry` per project, registered once at boot via `ErrorMappingInterceptor`.** *Why:* the interceptor sits in Dio's request pipeline and transforms `DioException` into `Either<Failure, T>` before the repository ever sees it. Multiple interceptors fight; the last wins; symptoms are hard to debug. Map the connectivity/timeout `dioRegistry` entries to a failure marked with the `TransportFailure` mixin (snh 1.3+) — repositories then preserve it via `mapBusiness` instead of a discard fold, so offline renders one app-wide message (failure-modeling Rule 5).

5. **Endpoint-specific error mappings live in the registry, not the repository.** *Why:* same reason as #3 — keeping the mapping in `endpointRegistry[FeatureApiPath.createItem]` means the failure rules for an endpoint are findable from one place, not scattered across repos.

6. **Set explicit timeouts on the Dio instance at boot** — `BaseOptions(connectTimeout: Duration(seconds: 5), receiveTimeout: Duration(seconds: 15))` (tune per backend). *Why:* Dio ships with NO timeouts; without them a request against a dead or hanging server waits forever — the user is stuck on a spinner and no `Failure` is ever produced. With timeouts, hangs become a normal transport error the registry maps like any other.

## Templates

- [API client](templates/api.dart) — Retrofit `@RestApi` with co-located `ApiPath` constants
- [Repository](templates/repository.dart) — abstract interface + `@LazySingleton` impl, both `@Generate` and manual `safeCall` shapes
- [ErrorRegistry](templates/error_registry.dart) — `endpointRegistry` + `dioRegistry` + `genericError`

## Reference

See [reference.md](reference.md) for:
- **(required reading)** Wiring `ErrorMappingInterceptor` into Dio at boot — the skill's templates won't work without this
- `@Generate` vs manual `safeCall` — when each pays off, and what the generated mixin looks like
- `ErrorRegistry` patterns: global `'*'`, endpoint-specific, treat-error-as-success
- `@Query`, `@Header`, `@FormData`, `@Field` Retrofit annotations beyond the basic `@Path` / `@Body`
- `onEndpointError` callback — for the rare case the registry can't express
- When the abstract `Repository` interface is worth keeping vs skipping
- Optional: named Dio clients (auth vs main) — only some projects need this
- Pagination patterns (limit/offset, cursor)
- Common mistakes table

Out of scope: retry/backoff middleware, offline caching, WebSocket / SSE streaming. The network skill stays focused on the request-response transport.

**Token refresh** is built into `simple_network_handler` v1.2.0+: wire `RefreshTokenInterceptor(tokenStore: ..., refreshToken: ... /* or refreshRequest: RefreshRequest(...) */, onRefreshFailed: ...)` into Dio **before** `ErrorMappingInterceptor` (refresh must see the 401 first; if refresh fails, the original error flows on to the registry). It single-flights concurrent 401s and runs the refresh + replay on a separate bare Dio — never hand-roll refresh logic in repositories or a custom interceptor. `TokenStore` is abstract: implement it over the project's secure storage.

→ After adding any `@RestApi` / `@Generate` / `@lazySingleton` annotation, rerun `dart run build_runner build --delete-conflicting-outputs`.

## Checklist

- [ ] `FeatureApiPath` class lives in the same file as `FeatureApi`
- [ ] All `@GET` / `@POST` / `@PUT` / `@DELETE` annotations reference `FeatureApiPath` constants — no raw strings
- [ ] Each `FeatureApiPath` constant is named after its Retrofit method (`getItemById`, not `itemById` or `clinicItemById`)
- [ ] `@RestApi()` + `@lazySingleton` on the API class (not eager `@singleton`)
- [ ] Repository impl is `@LazySingleton(as: FeatureRepository)` and returns the wide seam `Either<Failure, T>`
- [ ] Simple passthroughs use `@Generate(apiClient: FeatureApi)`; complex ops use `SimpleNetworkHandler.safeCall`
- [ ] No `try`/`catch` on `DioException` inside the repository — the registry handles transport errors
- [ ] `ErrorMappingInterceptor(AppErrorRegistry())` is added to Dio at boot, exactly once
- [ ] Dio `BaseOptions` sets explicit `connectTimeout` / `receiveTimeout`
- [ ] Endpoint-specific status codes are routed in `endpointRegistry`, not repository code
- [ ] Failures used here follow the `failure-modeling` skill (subclass of `Failure`, const constructors, `getTitle`/`getSubtitle`)
