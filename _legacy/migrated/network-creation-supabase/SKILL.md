---
name: network-creation-supabase
description: Implements Supabase-backed repositories using `simple_network_handler`'s Supabase variant. Repositories call `SupabaseClient.rpc()` / `client.from()` directly and convert transport errors to typed failures via `SupabaseErrorRegistry`. Use when the project depends on `supabase_flutter`, when repositories invoke `client.rpc()` / `client.from()`, when you need to choose between the error-envelope contract and the exception-coded contract for business failures, or when the user mentions Supabase, RPC, Postgrest, `.from()`, `.single()`, RLS, or `supabase_flutter`. Use INSTEAD OF the REST `network-creation` skill — Supabase repositories have no Retrofit API class and no `ApiPath` constants. Out of scope: Realtime subscriptions, Storage, Edge Functions (briefly noted; deserves its own skill).
---

# Network Creation — Supabase

For projects on `supabase_flutter` + `simple_network_handler` (v1.1+, Supabase entry-point). REST/Dio projects use the sibling `network-creation` skill — the two are mutually exclusive.

Failure shapes (`Failure` subclasses, `getTitle`/`getSubtitle`, code mappers) live in the `failure-modeling` skill — read it once, then come back here for transport.

## Architecture

```
Repository (abstract interface — optional)
    ↓
RepositoryImpl  ──→  SupabaseClient.rpc() / .from()
                    wrapped in SupabaseNetworkHandler.safeCall<T>
                    transport errors mapped by SupabaseErrorRegistry
```

The default shape has no API client class — the repository calls `SupabaseClient` directly. The transport handler + registry turn `AuthException`, `PostgrestException`, and network failures into typed `Failure`s. Business errors live somewhere else, and *where* depends on your backend's contract — that's the first decision below.

## API wrapper class — skip it by default

A `FeatureApi` class is **optional and usually skipped**. Inline `_client.rpc('rpc_name', params: {...})` / `_client.from('table')...` directly in the repository. The RPC name is one string literal the call site already shows; there's no Retrofit equivalent and nothing to generate.

Add a thin `FeatureApi` wrapper class **only when at least one of these is true**:

- The feature has **three or more RPC call sites** and you want the RPC names co-located in one file the way Retrofit clients have them in the REST skill.
- The same RPC is called from **two or more repositories** (rare — usually a sign the repository boundary is wrong; fix that first).
- The repository's tests mock the client surface and a plain Dart `FeatureApi` is materially easier to mock than `SupabaseClient`.

An `ApiPath`-constants-class **without** a wrapper class is not a useful midpoint — if the names appear at one call site each, inline them; if they appear in multiple call sites, you already justified the wrapper class.

When you do add one, keep it dumb: `Future<dynamic>`-returning methods, no `safeCall`, no error mapping — those stay in the repository. Annotate it `@injectable` (not `@singleton` — see Critical rule 7).

```dart
class FeatureApiPath {
  const FeatureApiPath._();
  static const String doThing = 'do_thing';
}

@injectable
class FeatureApi {
  FeatureApi(this._client);
  final SupabaseClient _client;

  Future<dynamic> doThing({required String id}) =>
      _client.rpc(FeatureApiPath.doThing, params: {'p_id': id});
}
```

The `account_deletion/` feature is the no-wrapper shape (preferred). `organization/` and `<feature>/` have wrappers that pre-date this rule — they are kept as-is, but new features default to no wrapper.

## First decision: which business-error contract does this RPC use?

Supabase backends report business errors in one of two ways. **The decision is per-RPC, not per-project** — most real codebases mix both. The repository code looks quite different for each, so pick before writing the method.

How to find out which contract a given RPC uses:
- Look at an existing call site in the codebase — if the method body has `safeCall<Map<String, dynamic>>(...).fold((_)=>..., (data) { final code = data['error']... })` it's Contract A; if it has `try { ... } on PostgrestException catch (e) { return Left(mapXxxErrorCode(e.message)); }` it's Contract B.
- Read the Postgres function source — `raise '<CODE>' using errcode = 'P0001'` is Contract B; `return jsonb_build_object('error', '<CODE>', ...)` is Contract A.
- Ask the backend team if neither is obvious.

**Contract A — error envelope (HTTP 200 + payload code).** RPC returns success status with `{ "error": "PLAN_INACTIVE", ...details }` in the body. The transport layer sees success; you check `data['error']` inside the success branch of the fold and route it through a code mapper.

**Contract B — exception code (`PostgrestException` carries the business code).** RPC raises `PostgrestException` with the business code in `e.message` or `e.code` (typically a Postgres `P0001` raise from a SQL function). The transport handler would auto-route it through the registry to `genericError`, which loses the code, so you intercept with a local `try/catch` and map `e.message` yourself.

Both patterns exist in real codebases. Often within the same project, because the choice is made per RPC by the backend team.

| Symptom in the response | Contract | Template |
|---|---|---|
| HTTP 200, JSON `{error: 'CODE', ...}` on failure | A — envelope | [repository_impl_envelope.dart](templates/repository_impl_envelope.dart) |
| HTTP 200, JSON object on success; throws on failure | B — exception code | [repository_impl_exception.dart](templates/repository_impl_exception.dart) |
| HTTP 4xx with body | Treat as transport — handle in `postgrestStatusRegistry` |
| Plain `.from()` query (no business logic) | Neither — transport-only |

## Critical rules

1. **Wrap every call site in `SupabaseNetworkHandler.safeCall<T>` OR in `try/catch` for the exception-coded pattern. Pick one per method — don't nest both.** *Why:* Mixing them double-handles errors and produces confusing stack traces.
2. **Specify the type parameter `<T>` on `safeCall` — pick the narrowest type that is correct in both the success and the error-envelope branch.** `Map<String, dynamic>` for single-object responses (including Contract A envelopes — the error envelope is also a map). `List<dynamic>` for arrays without an envelope. `dynamic` *only* when success and failure have different runtime types (e.g. list-on-success vs map-envelope-on-failure). *Why:* Omitting `<T>` pushes runtime errors downstream; over-widening to `<dynamic>` forces an `is Map` check the caller doesn't need when both shapes are already maps.
3. **Inject `SupabaseClient` via the constructor — never read `Supabase.instance.client` inside methods.** *Why:* Constructor injection makes the repo unit-testable with a mock client and surfaces the dependency in DI graph audits.
4. **Don't expose `SupabaseClient` outside the repository.** *Why:* The repository is the seam where transport exceptions become typed `Failure`s. Cubits and widgets that hold the client can accidentally bypass the registry.
5. **Initialize the registry once at app boot, after `Supabase.initialize(...)`.** *Why:* `SupabaseNetworkHandler.setErrorRegistry` is global state. Multiple calls fight; the last wins.
6. **Pass Postgres `date` parameters as `'YYYY-MM-DD'` strings, not `DateTime.toIso8601String()`.** *Why:* Postgres `date` columns reject datetime literals — you'll get a coercion error at the SQL layer.
7. **Annotate repositories and any `*Api` wrappers with `@injectable` / `@Injectable(as: FeatureRepository)` — not `@singleton` or `@lazySingleton`.** *Why:* `core-architecture.md` forbids `@singleton` without explicit user approval — singletons hold state for the app's lifetime with wide blast radius and repositories are stateless transport adapters. Existing `@singleton` annotations in the codebase (`LegacyExampleApi`, `SomeApi`) pre-date this rule and are kept as-is, but do not propagate them to new code.

## Templates

- [Abstract repository interface](templates/repository.dart) — optional, drop if you don't need test doubles or env-specific impls
- [Repository impl — envelope contract](templates/repository_impl_envelope.dart) — two-phase fold; use when backend returns `{error: 'CODE'}` on HTTP 200
- [Repository impl — exception-coded contract](templates/repository_impl_exception.dart) — try/catch on `PostgrestException`; use when backend raises with code in `e.message`
- [SupabaseErrorRegistry subclass](templates/error_registry.dart) — auth code map + Postgrest status map + generic fallback

## Reference

See [reference.md](reference.md) for:
- Full `SupabaseErrorRegistry` structure and the standard supabase-go-true auth codes worth mapping
- Choosing the right `<T>` for `safeCall<T>` (RPC single-object, RPC list, `.from()`, `.single()`, `.maybeSingle()`, mutations)
- `.from()` query patterns: `.single()`, `.maybeSingle()`, `.insert()`, `.update()`, `.delete()`, `.upsert()`
- Calling Edge Functions via `client.functions.invoke(...)` (brief — Edge Functions need their own skill for full coverage)
- Multi-RPC mappers (when one code string means different things on different RPCs) and pagination via `.range()`
- Postgres parameter conventions (dates, UUIDs, enums)
- Whether to keep the abstract interface or skip it
- Common mistakes table

→ After adding any `@injectable` / `@Injectable(as: ...)` annotation on a new repository or `*Api` wrapper, rerun `dart run build_runner build --delete-conflicting-outputs`. Full workflow + recovery: `/code-generation-workflow`.

## Checklist

- [ ] Identified each RPC's contract (A envelope / B exception-coded) by reading existing call sites, the Postgres function source, or asking the backend team — and used the matching template per method
- [ ] All Supabase calls go through `SupabaseNetworkHandler.safeCall<T>` (Contract A) or a local `try/catch` (Contract B), with explicit type parameter
- [ ] `SupabaseClient` is injected via the constructor, not read via `Supabase.instance.client` inside methods
- [ ] For Contract A: success branch checks `data['error']` and routes through `mapFeatureErrorCode`
- [ ] For Contract B: `on PostgrestException catch (e)` maps `e.message`; bare `catch (_)` falls back to a transport failure
- [ ] Dates passed to Postgres `date` columns are `'YYYY-MM-DD'`-formatted strings
- [ ] `AppSupabaseErrorRegistry.initialize()` is called once at app boot after `Supabase.initialize(...)`
- [ ] Repository (and optional `FeatureApi` wrapper) is annotated `@injectable` / `@Injectable(as: ...)` — not `@singleton`
- [ ] Failures used here follow the `failure-modeling` skill (subclass of `Failure`, const constructors, `getTitle`/`getSubtitle`)
