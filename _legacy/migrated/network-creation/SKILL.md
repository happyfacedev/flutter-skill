---
name: network-creation
description: Implements REST network layer components for Dio + Retrofit projects using `simple_network_handler` (v1.1+). Covers Retrofit `@RestApi` clients with co-located `ApiPath` constants, `Either<Failure, T>` repositories with optional `@Generate` mixin from `simple_repository_generator`, the `ErrorRegistry` pattern (global + endpoint-specific status maps + `dioRegistry` for transport-level exceptions), and wiring `ErrorMappingInterceptor` into Dio. Use when the project depends on `dio` + `retrofit`, when repositories call a generated `_FeatureApi`, when failures need to be routed by endpoint + HTTP status, or when the user mentions Retrofit, Dio, `@RestApi`, `ApiPath`, REST endpoint, `@Body`, `@Path`, `@Generate`, or `ErrorMappingInterceptor`. Use INSTEAD OF `network-creation-supabase` — REST projects have an explicit API client class and stable endpoint paths; Supabase projects don't.
---

# Network Creation — REST (Dio + Retrofit)

For projects on `dio` + `retrofit` + `simple_network_handler` (v1.1+). Supabase projects use the sibling `network-creation-supabase` skill — the two are mutually exclusive.

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
2. **`FeatureRepository`** — abstract (optional) + `@Injectable(as: FeatureRepository)` impl. Returns `Either<FeatureFailure, T>`. Simple passthrough methods can use `@Generate(apiClient: FeatureApi)` from `simple_repository_generator` to skip the manual `safeCall` boilerplate.
3. **`AppErrorRegistry`** — single project-wide subclass of `ErrorRegistry`. Wired into Dio via `ErrorMappingInterceptor` at boot.

## Critical rules

1. **Never raw-string an endpoint path. Use `@GET(FeatureApiPath.getItems)`, not `@GET('/api/feature/items')`.** *Why:* the `FeatureApiPath` class is the one source of truth for endpoints — grep finds all uses, the registry's endpoint-specific entries reference the same constants, and a backend URL change touches one line instead of many.

    **Name each constant after the Retrofit method that uses it** — `getItems`, `getItemById`, `createItem`, `searchTests` — one constant per method, lowerCamelCase. *Why:* the registry reads `endpointRegistry[FeatureApiPath.createItem]` and the repo reads `apiClient.createItem(...)` — using the same name on both sides makes the link obvious. Resource-only names (`items`, `clinicLocation`) collide when two methods share a URL (`GET /items` and `POST /items`).

2. **Annotate API clients with `@injectable` (factory), not `@singleton`.** *Why:* a Retrofit client is stateless. A singleton extends its lifetime for no benefit and gives it global blast radius. Use `@lazySingleton` only when there's a deliberate caching reason (e.g. you've added in-memory response caching to the client itself).

3. **Wrap every repository call in `SimpleNetworkHandler.safeCall<T>` OR use `@Generate`. Don't mix manual `try/catch` with the registry.** *Why:* both routes funnel errors through the registry. Local `try/catch` on `DioException` duplicates the registry's work and produces two sources of truth for "what failure does a 403 become?"

4. **One `ErrorRegistry` per project, registered once at boot via `ErrorMappingInterceptor`.** *Why:* the interceptor sits in Dio's request pipeline and transforms `DioException` into `Either<Failure, T>` before the repository ever sees it. Multiple interceptors fight; the last wins; symptoms are hard to debug.

5. **Endpoint-specific error mappings live in the registry, not the repository.** *Why:* same reason as #3 — keeping the mapping in `endpointRegistry[FeatureApiPath.createItem]` means the failure rules for an endpoint are findable from one place, not scattered across repos.

## Templates

- [API client](templates/api.dart) — Retrofit `@RestApi` with co-located `ApiPath` constants
- [Repository](templates/repository.dart) — abstract interface + `@Injectable` impl, both `@Generate` and manual `safeCall` shapes
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

Out of scope: retry/backoff middleware, offline caching, WebSocket / SSE streaming. Wire those on top of repositories with project-level patterns; the network skill stays focused on the request-response transport.

→ After adding any `@RestApi` / `@Generate` / `@injectable` annotation, rerun `dart run build_runner build --delete-conflicting-outputs`. Full workflow + recovery: `/code-generation-workflow`.

## Checklist

- [ ] `FeatureApiPath` class lives in the same file as `FeatureApi`
- [ ] All `@GET` / `@POST` / `@PUT` / `@DELETE` annotations reference `FeatureApiPath` constants — no raw strings
- [ ] Each `FeatureApiPath` constant is named after its Retrofit method (`getItemById`, not `itemById` or `clinicItemById`)
- [ ] `@RestApi()` + `@injectable` on the API class (not `@singleton` unless justified)
- [ ] Repository impl is `@Injectable(as: FeatureRepository)` and returns `Either<FeatureFailure, T>`
- [ ] Simple passthroughs use `@Generate(apiClient: FeatureApi)`; complex ops use `SimpleNetworkHandler.safeCall`
- [ ] No `try`/`catch` on `DioException` inside the repository — the registry handles transport errors
- [ ] `ErrorMappingInterceptor(AppErrorRegistry())` is added to Dio at boot, exactly once
- [ ] Endpoint-specific status codes are routed in `endpointRegistry`, not repository code
- [ ] Failures used here follow the `failure-modeling` skill (subclass of `Failure`, const constructors, `getTitle`/`getSubtitle`)
