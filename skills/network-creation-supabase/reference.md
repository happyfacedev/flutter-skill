# Network Creation (Supabase) — Reference

## `SupabaseErrorRegistry` structure

A single Supabase call can fail in multiple ways — authentication codes from Supabase Auth, HTTP status codes from Postgrest, or business codes you've decided to handle locally. The registry has three slots, each catching a different failure mode.

### `authErrorRegistry` — `Map<String, Failure Function(AuthException)>`

Keys are string codes from `AuthException.code` (Supabase Auth / go-true). Standard codes worth mapping in most apps:

| Code | Meaning |
|---|---|
| `invalid_credentials` | Email/password mismatch on sign-in |
| `user_not_found` | No user for this email (sign-in / reset password) |
| `email_not_confirmed` | Sign-in attempted before clicking verification email |
| `user_already_exists` | Sign-up with an email that's already registered |
| `weak_password` | Password doesn't meet policy (length/complexity) |
| `session_expired` | Refresh token invalid — log the user out |
| `email_address_invalid` | Server-side email validation failed |
| `over_email_send_rate_limit` | Too many magic-link / OTP sends |

Map only the codes your UI distinguishes. Unknown codes fall through to `genericError`.

### `postgrestStatusRegistry` — `Map<int, Either Function(PostgrestException, String?, int)>`

Keys are HTTP status codes from `PostgrestException`. The callback returns `Either<Failure, dynamic>` — wrap `Left(...)` is usual, but `Right(null)` lets you treat some statuses as success.

```dart
401: (e, m, code) => const Left(SessionExpiredFailure()),       // JWT expired
403: (e, m, code) => const Left(ForbiddenFailure()),            // RLS deny
404: (e, m, code) => const Left(GenericFailure(...)),           // missing row
409: (e, m, code) => const Left(ConflictFailure()),             // unique violation
422: (e, m, code) => const Left(ValidationFailure()),           // check constraint
```

Postgrest doesn't expose stable "endpoint" strings, so there's no endpoint-specific routing here. Per-RPC error handling goes in the **business** layer (envelope or exception-coded), not the registry.

### `genericError` — `Failure`

Fallback when nothing else matches. Network failures, unknown exceptions, parse errors. Usually `GenericFailure` from `core/failures/`.

## Choosing `<T>` on `safeCall<T>`

`safeCall<T>` types the right side of the resulting `Either`. Picking `T` correctly removes a `dynamic` cast downstream.

| Call shape | `<T>` |
|---|---|
| `_client.rpc('x')` returns single object, no error envelope | `Map<String, dynamic>` |
| `_client.rpc('x')` returns single object on success **or** `{error: 'CODE'}` envelope on failure (Contract A) | `Map<String, dynamic>` — both shapes are maps; check `data['error']` in the fold |
| `_client.rpc('x')` returns array, no error envelope | `List<dynamic>` |
| `_client.rpc('x')` returns array on success **or** `{error: 'CODE'}` envelope on failure | `dynamic` — different runtime types; branch on `is List` vs `is Map` |
| `_client.from('t').select()` | `List<dynamic>` |
| `_client.from('t').select().single()` | `Map<String, dynamic>` |
| `_client.from('t').select().maybeSingle()` | `Map<String, dynamic>?` |
| `.insert(row)` / `.update(...)` / `.delete()` (no select) | `dynamic` or `void` — discard result |
| `.insert(row).select().single()` (returning inserted row) | `Map<String, dynamic>` |

**Rule of thumb:** use the narrowest type that is correct in both the success and the envelope branch. Fall back to `dynamic` only when success and failure are different Dart runtime types (list vs map) — not just because the response *might* be an envelope.

For the "single-object happy or error-envelope unhappy" case — both shapes are `Map<String, dynamic>`, so stay narrow. Map with `mapBusiness` (wide `Either<Failure, T>` seam — Critical rule 7): transport failures pass through unchanged, the feature fallback covers genuine server errors:

```dart
final result = await SupabaseNetworkHandler.safeCall<Map<String, dynamic>>(
  () => _client.rpc('do_thing', params: {...}),
);
return result.mapBusiness(
  const FeatureUnknownFailure(),
  (data) {
    final code = data['error'] as String?;
    if (code != null) return Left(mapFeatureErrorCode(code, payload: data));
    return Right(FeatureResponse.fromJson(data));
  },
);
```

For the "array happy or error-envelope unhappy" case — the shapes disagree, so fall back to `dynamic` and branch on type:

```dart
final result = await SupabaseNetworkHandler.safeCall<dynamic>(
  () => _client.rpc('list_things_or_error'),
);
return result.mapBusiness(
  const FeatureUnknownFailure(),
  (data) {
    if (data is Map<String, dynamic>) {
      final code = data['error'] as String?;
      if (code != null) return Left(mapFeatureErrorCode(code, payload: data));
    }
    if (data is! List) return const Left(FeatureUnknownFailure());
    final things = data
        .map((row) => FeatureResponse.fromJson(row as Map<String, dynamic>))
        .toList();
    return Right(things);
  },
);
```

## `.from()` patterns

### Single-row fetch (`.single()` vs `.maybeSingle()`)

`.single()` throws `PostgrestException` if zero or more than one row is returned. `.maybeSingle()` returns `null` for zero rows and throws only on multiple. Pick by intent:

- "this row must exist, missing is an error" → `.single()`
- "this row may not exist, missing is a normal case" → `.maybeSingle()`

```dart
// Single — caller treats missing as failure:
final result = await SupabaseNetworkHandler.safeCall<Map<String, dynamic>>(
  () => _client.from('profiles').select().eq('id', id).single(),
);

// Maybe-single — caller handles null explicitly:
final result = await SupabaseNetworkHandler.safeCall<Map<String, dynamic>?>(
  () => _client.from('profiles').select().eq('id', id).maybeSingle(),
);
return result.mapBusiness(
  const FeatureUnknownFailure(),
  (row) => row == null
      ? const Right(null)
      : Right(FeatureResponse.fromJson(row)),
);
```

### Mutations

```dart
// Insert returning the new row:
final result = await SupabaseNetworkHandler.safeCall<Map<String, dynamic>>(
  () => _client.from('things').insert({'name': name}).select().single(),
);

// Update returning nothing (discard result):
final result = await SupabaseNetworkHandler.safeCall<dynamic>(
  () => _client.from('things').update({'name': name}).eq('id', id),
);

// Delete returning nothing:
final result = await SupabaseNetworkHandler.safeCall<dynamic>(
  () => _client.from('things').delete().eq('id', id),
);

// Upsert (insert or update on conflict):
final result = await SupabaseNetworkHandler.safeCall<dynamic>(
  () => _client.from('things').upsert({'id': id, 'name': name}),
);
```

### Pagination (`.range()`)

`.range(from, to)` is inclusive on both ends.

```dart
final result = await SupabaseNetworkHandler.safeCall<List<dynamic>>(
  () => _client
      .from('things')
      .select()
      .order('created_at', ascending: false)
      .range(offset, offset + limit - 1),
);
```

## `client.rpc()` vs `client.from()`

| Use `rpc()` when... | Use `from()` when... |
|---|---|
| Business logic lives in a Postgres function | You need raw CRUD against a table or view |
| The backend wants atomic invariants | RLS policies are sufficient access control |
| The function returns a business error envelope | The query is straightforward select/insert/update |
| You combine reads + writes in one round trip | You want to filter/order/paginate declaratively |

## Calling Edge Functions (brief)

Edge Functions are HTTP endpoints; `_client.functions.invoke('fn-name', body: {...})` calls them. They throw `FunctionException` on non-2xx. The registry doesn't currently have a slot for `FunctionException`, so wrap call sites in a local `try/catch` similar to Contract B:

```dart
try {
  final res = await _client.functions.invoke('fn-name', body: {...});
  return Right(FeatureResponse.fromJson(res.data as Map<String, dynamic>));
} on FunctionException catch (e) {
  return Left(mapFeatureErrorCode(e.details?.toString() ?? ''));
} catch (e) {
  // Raw try/catch bypasses safeCall, so transport is NOT auto-classified —
  // a dead socket lands here. Classify it first, like Contract B (shared
  // predicate from lib/core/failures/offline_failure.dart).
  if (isTransportError(e)) return const Left(OfflineFailure());
  return const Left(FeatureUnknownFailure());
}
```

Full Edge Function support — auth header propagation, FunctionException → registry mapping, streaming responses — deserves its own skill. This is the bare minimum.

## Multi-RPC code mapper

Default: **one `map<Feature>ErrorCode` function per feature**, shared across every RPC in that feature. When you add a second RPC to a feature that already has a mapper, extend the existing switch — do not create `mapDoSecondThingErrorCode` alongside it.

Parameterise the mapper with an RPC enum **only** when the same code string carries different meanings on different RPCs — e.g. `NOT_FOUND` means "thing missing" on `do_thing` but "already undone" on `undo_thing`. That's the collision that justifies the parameter; "both RPCs happen to return `NOT_FOUND` and it means the same thing" is not.

```dart
enum FeatureRpc { doThing, undoThing }

FeatureFailure mapFeatureErrorCode(
  String code, {
  Map<String, dynamic>? payload,
  FeatureRpc rpc = FeatureRpc.doThing,
}) {
  if (rpc == FeatureRpc.undoThing && code == 'NOT_FOUND') {
    return const FeatureAlreadyUndoneFailure();
  }
  // ... usual switch, codes that mean the same thing on both RPCs
}
```

Most features never have a collision. Skip the enum until you find one.

## Postgres parameter conventions

| Dart value | RPC param | Notes |
|---|---|---|
| `DateTime` for a `date` column | `'YYYY-MM-DD'` string | Postgres `date` rejects ISO 8601 datetimes |
| `DateTime` for a `timestamptz` column | `dt.toUtc().toIso8601String()` | Use UTC; let Postgres convert |
| `String` UUID | plain string | Postgres parses it |
| Dart `enum` | `enum.name` (snake_case) | If Postgres enum is `'active' \| 'inactive'`, send `'active'` |
| `null` | `null` | Postgres treats as SQL `NULL` |
| `List<T>` | JSON array | `params['p_ids']: ['a', 'b']` |

Helper for dates (paste if you have several `date` params):

```dart
String _dateParam(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
```

## Should the abstract interface be skipped?

The interface pays off when:
- Test doubles needed — a fake impl for cubit unit tests
- Env-specific implementations — e.g. offline mock for dev
- Subset exposure — impl has internal helpers you don't want public

Otherwise skip — `@lazySingleton class FeatureRepository { ... }` is fine. Don't add abstraction speculatively.

## Out of scope (use other skills / future skills)

- **Realtime subscriptions** (`_client.channel('x').on(...)`) — no skill yet; pattern is stream-based, not request-response
- **Storage** (`_client.storage.from('bucket')`) — separate concern (file uploads, signed URLs)
- **Auth flows** (sign-in/up/reset/OTP) — these *use* the registry but the cubit-level orchestration belongs in cubit-creation
- **Retry / backoff** — wrap call sites with your project's retry middleware; not a transport concern
- **Offline caching** — feature-level decision (Hive, drift, isar); the repo signature stays `Either<Failure, T>`

## Common mistakes

| ❌ Don't | ✅ Do |
|----------|-------|
| `_client.rpc('x')` directly in repo (no wrapping) | `SupabaseNetworkHandler.safeCall<T>(...)` or `try/catch on PostgrestException` |
| `safeCall(() => ...)` (no type) | `safeCall<Map<String, dynamic>>(() => ...)` |
| Ignore `data['error']` in success branch (Contract A) | Check it; route through `mapFeatureErrorCode` |
| Nest `try/catch` inside `safeCall` | Pick one mechanism per method |
| `Supabase.instance.client` inside a method | Inject `SupabaseClient` via constructor |
| `date.toIso8601String()` for a `date` column | `'YYYY-MM-DD'` string |
| Initialize registry inside a cubit | Initialize once at app boot after `Supabase.initialize` |
| `safeCall<dynamic>` everywhere | Use the narrowest `<T>` that matches the response shape (exception: `FeatureApi`-seam calls are `safeCall<dynamic>` + explicit cast — Critical rule 2) |
| `@Singleton(as: FeatureRepository)` (copied from existing `*Api` classes) | `@LazySingleton(as: FeatureRepository)` — Critical rule 9; eager singleton scope needs explicit user approval |
| Add a `FeatureApi` wrapper "to match the pattern" | Skip it unless a SKILL.md trigger applies — writing the Impl's unit test always triggers it |

## File layout

```
lib/
├── core/
│   ├── failures/
│   │   └── generic_failure.dart            # see failure-modeling
│   └── network/
│       └── app_supabase_error_registry.dart
└── features/
    └── <feature>/
        └── logic/
            ├── failures/
            │   └── <feature>_failure.dart  # see failure-modeling
            ├── models/
            │   ├── responses/
            │   └── request_bodies/
            └── repositories/
                ├── <feature>_repository.dart       # abstract (optional)
                └── <feature>_repository_impl.dart  # @LazySingleton(as:) impl
```
