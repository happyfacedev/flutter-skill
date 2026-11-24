---
name: network-creation-supabase
description: Internal flutter-skill pattern — invoked via the flutter-skill router, not from this description. (Supabase repositories, RPC, Postgrest.)
---

# Network Creation — Supabase

For projects on `supabase_flutter` + `simple_network_handler` (v1.3+, Supabase entry-point). REST/Dio projects use the sibling `network-creation` skill — the two are mutually exclusive.

Failure shapes (`Failure` subclasses, `getTitle`/`getSubtitle`, code mappers) live in the `failure-modeling` skill — read it once, then come back here for transport.

## Architecture

```
Repository (abstract interface — optional)
    ↓
RepositoryImpl  ──→  SupabaseClient.rpc() / .from()
                    wrapped in SupabaseNetworkHandler.safeCall<T>
                    transport errors mapped by SupabaseErrorRegistry
```

The default shape has no API client class — the repository calls `SupabaseClient` directly. The transport handler + registry turn `AuthException`, `PostgrestException`, and network failures into typed `Failure`s. Repositories return the wide seam `Either<Failure, T>` and map results with `mapBusiness`, so transport failures (offline/timeout) pass through unchanged app-wide (Critical rule 7). Business errors live somewhere else, and *where* depends on your backend's contract — that's the first decision below.

## API wrapper class — skip it by default

A `FeatureApi` class is **optional and usually skipped**. Inline `_client.rpc('rpc_name', params: {...})` / `_client.from('table')...` directly in the repository. The RPC name is one string literal the call site already shows; there's no Retrofit equivalent and nothing to generate. One standing exception: an Impl that is getting unit tests always adds the wrapper — trigger 3 below.

Add a thin `FeatureApi` wrapper class **only when at least one of these is true**:

- The feature has **three or more RPC call sites** and you want the RPC names co-located in one file the way Retrofit clients have them in the REST skill.
- The same RPC is called from **two or more repositories** (rare — usually a sign the repository boundary is wrong; fix that first).
- The repository's tests mock the client surface and a plain Dart `FeatureApi` is materially easier to mock than `SupabaseClient`. **Writing the Impl's unit test always satisfies this trigger** — extract the seam even below the other thresholds whenever the repository gets tests; reactive repositories in practice always qualify (see `/unit-testing`).

An `ApiPath`-constants-class **without** a wrapper class is not a useful midpoint — if the names appear at one call site each, inline them; if they appear in multiple call sites, you already justified the wrapper class.

When you do add one, keep it dumb: `Future<dynamic>`-returning methods, no `safeCall`, no error mapping — those stay in the repository. Annotate it `@lazySingleton` (not eager `@singleton` — see Critical rule 9).

```dart
class FeatureApiPath {
  const FeatureApiPath._();
  static const String doThing = 'do_thing';
}

@lazySingleton
class FeatureApi {
  FeatureApi(this._client);
  final SupabaseClient _client;

  Future<dynamic> doThing({required String id}) =>
      _client.rpc(FeatureApiPath.doThing, params: {'p_id': id});
}
```

Existing wrapper classes that pre-date this rule are kept as-is, but new features default to the no-wrapper shape.

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
2. **Specify the type parameter `<T>` on `safeCall` — pick the narrowest type that is correct in both the success and the error-envelope branch.** `Map<String, dynamic>` for single-object responses (including Contract A envelopes — the error envelope is also a map). `List<dynamic>` for arrays without an envelope. `dynamic` *only* when success and failure have different runtime types (e.g. list-on-success vs map-envelope-on-failure). *Why:* Omitting `<T>` pushes runtime errors downstream; over-widening to `<dynamic>` forces an `is Map` check the caller doesn't need when both shapes are already maps. Exception — calls routed through a `FeatureApi` seam: the seam's dumb `Future<dynamic>` methods force `safeCall<dynamic>(_api.method)` with an explicit cast inside the guarded mapping block; narrowest-`<T>` applies to direct `_client` calls.
3. **Inject `SupabaseClient` via the constructor — never read `Supabase.instance.client` inside methods.** *Why:* Constructor injection surfaces the dependency in DI graph audits and gives tests a swappable transport. Note: Impl unit tests still never mock `SupabaseClient` itself (a mocked client can't resolve to response data) — they mock a thin `FeatureApi` seam instead; see `/unit-testing`'s doubles table and the API-wrapper triggers above.
4. **Don't expose `SupabaseClient` outside the repository.** *Why:* The repository is the seam where transport exceptions become typed `Failure`s. Cubits and widgets that hold the client can accidentally bypass the registry.
5. **Initialize the registry once at app boot, after `Supabase.initialize(...)`.** *Why:* `SupabaseNetworkHandler.setErrorRegistry` is global state. Multiple calls fight; the last wins.
6. **Pass Postgres `date` parameters as `'YYYY-MM-DD'` strings, and `timestamptz` parameters as `.toUtc().toIso8601String()`.** *Why:* `date` columns reject datetime literals (SQL-layer coercion error); and Dart's plain `toIso8601String()` on a LOCAL DateTime omits the timezone offset, silently corrupting `timestamptz` semantics — always convert to UTC first.
7. **Keep the seam wide — `Either<Failure, T>`, never `Either<FeatureFailure, T>` — and never discard the failure `safeCall` hands you.** Propagate it (`fold(Left.new, ...)`), or substitute a feature fallback for business errors with `result.mapBusiness(const FeatureUnknownFailure(), onData)` — never a discard fold (`(_) => const Left(...)`). *Why:* the registry already classified the error inside `safeCall` — transport became the app's `OfflineFailure` (a `TransportFailure`, snh 1.3+), auth/Postgrest codes got specific failures with localized copy. A feature-typed seam or a discard fold erases that; `mapBusiness` passes `TransportFailure` through unchanged, so offline renders one app-wide message while genuine server errors keep their feature copy.

   **Paths that bypass `safeCall` classify transport themselves:** a fold with custom left routing keeps `if (failure is TransportFailure) return Left(failure);` as its first branch, and Contract B / Edge Function raw catches start with `if (isTransportError(e)) return const Left(OfflineFailure());`. Both helpers live in one file — [templates/offline_failure.dart](templates/offline_failure.dart) — never re-derive the check locally.

8. **`_client.auth.currentUser` is `null` when signed out or the session expired — treat that as a typed auth failure** (`if (user == null) return const Left(<AuthFailure>);`), per the core no-force-unwrap rule.

9. **Annotate repositories and any `*Api` wrappers with `@lazySingleton` / `@LazySingleton(as: FeatureRepository)` — not eager `@singleton`.** *Why:* one lazily-created instance app-wide is the standard lifetime for stateless transport adapters; eager `@singleton` (app-start construction, wide blast radius) still needs explicit user approval. Existing annotations that pre-date this rule are kept as-is.

10. **Know the RLS asymmetry before mapping errors.** A SELECT blocked by row-level security **silently returns an empty result — no error** — so never map "empty" to a not-found failure without ruling out a policy/JWT problem. Writes that violate RLS **throw `42501`**. And `.insert(...).select()` runs the returned-row read under the SELECT policy: a **successful write can surface as PGRST116** — a visibility error, not a write error — so never blindly retry a mutation on it (the write already committed; retrying duplicates it). Pair every INSERT policy with a SELECT policy, or skip `.select()` after the insert.

## Templates

- [Abstract repository interface](templates/repository.dart) — optional, drop if you don't need test doubles or env-specific impls
- [Repository impl — envelope contract](templates/repository_impl_envelope.dart) — `mapBusiness` over the `safeCall` result; use when backend returns `{error: 'CODE'}` on HTTP 200
- [Repository impl — exception-coded contract](templates/repository_impl_exception.dart) — try/catch on `PostgrestException`; use when backend raises with code in `e.message`
- [OfflineFailure + transport predicate](templates/offline_failure.dart) — `lib/core/failures/offline_failure.dart`: the `TransportFailure`-marked connectivity failure and the shared `isTransportError()` used by the registry and every raw catch
- [SupabaseErrorRegistry subclass](templates/error_registry.dart) — auth code map + Postgrest status map + transport classification + generic fallback. **Greenfield only** — an established project already has a live registry carrying app plumbing (transport classification, session-expiry marking); extend that one, never regenerate from the template

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

→ After adding any `@lazySingleton` / `@LazySingleton(as: ...)` annotation on a new repository or `*Api` wrapper, rerun `dart run build_runner build --delete-conflicting-outputs`.

## Checklist

- [ ] Identified each RPC's contract (A envelope / B exception-coded) by reading existing call sites, the Postgres function source, or asking the backend team — and used the matching template per method
- [ ] All Supabase calls go through `SupabaseNetworkHandler.safeCall<T>` (Contract A) or a local `try/catch` (Contract B), with explicit type parameter
- [ ] Repository returns the wide seam `Either<Failure, T>` and maps with `mapBusiness` (no feature-typed seam, no discard fold) so `TransportFailure` passes through — Critical rule 7
- [ ] `SupabaseClient` is injected via the constructor, not read via `Supabase.instance.client` inside methods
- [ ] `_client.auth.currentUser` is null-checked (typed auth failure when absent) — never force-unwrapped
- [ ] For Contract A: success branch checks `data['error']` and routes through `mapFeatureErrorCode`
- [ ] For Contract B: `on PostgrestException catch (e)` maps `e.message`; the bare `catch (e)` classifies transport FIRST (the shared `isTransportError` from `offline_failure.dart` → `OfflineFailure`) before the feature fallback — the raw try/catch bypasses `safeCall`, so nothing classifies transport for you
- [ ] Dates passed to Postgres `date` columns are `'YYYY-MM-DD'`-formatted strings; `timestamptz` params go through `.toUtc().toIso8601String()`
- [ ] Empty SELECT results not mapped to not-found without considering RLS; mutations never retried on PGRST116 after `.insert().select()`
- [ ] `AppSupabaseErrorRegistry.initialize()` is called once at app boot after `Supabase.initialize(...)`
- [ ] Repository (and optional `FeatureApi` wrapper) is annotated `@lazySingleton` / `@LazySingleton(as: ...)` — not eager `@singleton`
- [ ] Failures used here follow the `failure-modeling` skill (subclass of `Failure`, const constructors, `getTitle`/`getSubtitle`)
