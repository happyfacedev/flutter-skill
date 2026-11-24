# Failure Modeling

The `Failure` base class is shared by both transports — REST projects import it from `package:simple_network_handler/simple_network_handler.dart`, Supabase projects from `package:simple_network_handler/simple_network_handler_supabase.dart`. Either way: repositories return `Either<Failure, T>`; cubits route failures to the UI via `addError` or `emit`; the UI calls `failure.getTitle(context)` / `failure.getSubtitle(context)` to render them.

This skill covers the **shape** of failures. Transport-level catching (turning `DioException` / `PostgrestException` into a `Failure`) lives in the network skills.

## First: does the failure already exist?

Before scaffolding a new `<Feature>Failure` or adding a new concrete subclass, search `lib/features/**/logic/failures/` and `lib/core/failures/` for the *condition* you're modelling. Class-full, already-booked, plan-inactive, slot-unavailable — these are domain facts, not action labels. If an existing feature already names the fact, reuse the existing class.

- When a new RPC operates on the same domain as an existing feature (e.g. a new RPC on the existing `items/` feature), extend that feature's hierarchy with the *net-new* subclasses and extend its mapper — don't fork a parallel hierarchy in a new feature folder.
- The feature-isolation rule (flutter-skill core rules) forbids cross-feature imports of *cubits and repositories*. Failure classes are domain primitives — the same category as shared models — so when the new RPC genuinely operates in the existing feature's domain, the import is expected. If the rule blocks you because the failures should be shared more broadly, promote them as below.
- When two or more features end up consuming the same failure, promote it to `lib/core/failures/<domain>_failure.dart` (move the file, update importers, rerun build_runner). Don't promote speculatively — wait for the second importer.

*Why:* duplicating a failure across features splits the mapper, the ARB keys, and the snackbar copy for one underlying business fact. Tests can't `expect` a single type, and the next backend rename has to touch both hierarchies.

## Decision: single catch-all, or hierarchy?

Pick before writing the first failure for a feature — switching later is a refactor. Once chosen, go to the matching template.

**Single `GenericFailure` (in `core/failures/`) → use [single_failure.dart](templates/single_failure.dart)** when:
- The feature has one "things went wrong" surface and the UI doesn't branch on error kind
- The backend doesn't return distinguishable error codes (just success or 5xx)
- The error renders as one snackbar message and the user retries

**Abstract `FeatureFailure` + concrete subclasses → use [feature_failure.dart](templates/feature_failure.dart)** when:
- The backend returns business error codes the UI cares about (e.g. `PLAN_INACTIVE`, `RATE_LIMITED`) with different copy / different UI per code
- A failure carries data (deadline timestamp, attempts remaining, related ID) the UI displays
- One or two cases need bespoke routing (e.g. rate limit → inline banner instead of snackbar)

Mixing is fine: a project usually has one `GenericFailure` plus a `FooFailure` hierarchy in features that need it.

## Critical rules

1. **`Failure` is the only return-type for the left side of `Either` in repositories.** *Why:* the cubit layer assumes `Failure` so the global BlocObserver can render `getTitle`/`getSubtitle`. Returning `Exception` or `String` breaks the contract and forces every cubit to special-case display.

2. **Localize at render time (`getTitle(context)`), not construction time.** *Why:* failures stay `const`-constructible and unit-testable without pumping a widget tree. The constructor stores only the code and a non-localized fallback message.

3. **Keep failure constructors `const`.** *Why:* failures are value objects allocated on every error. `const` lets the VM share instances and enables compile-time equality.

4. **Don't write `try/catch` solely to re-wrap a transport exception into a generic failure.** *Why:* the registry already classifies transport exceptions — via the `isTransportError`/`transportError` hooks (snh 1.3+), the app's registry maps them to its `OfflineFailure` (a `TransportFailure`; registry + failure templates in the network skill). A repo-level `try` that does only `catch (DioException e) { return Left(NetworkFailure()); }` duplicates that work and forks the source of truth. **Distinction:** reading a business error code *out of* a caught exception (e.g. mapping `e.message` in the Supabase exception-coded contract) is not redundant wrapping — the exception is the carrier of business information, and the catch is the only place to extract it. That's a deliberate pattern, documented in the `network-creation-supabase` skill.

5. **A hierarchy has exactly one fallback variant — `<Feature>UnknownFailure` — covering unknown business codes and unclassified server errors.** Don't split into separate `<Feature>NetworkFailure` and `<Feature>UnknownFailure`; don't name it after the action (`ItemRedemptionFailure`); don't split per operation (`<Feature>FetchFailure` + `<Feature>UpdateFailure` with no distinct business codes behind them) — the cubit already knows which method failed, so which-action-failed is calling context, not information to encode in failure subclasses. *Why:* transport-tier errors never reach the feature fallback at all — the app's registry classifies them as `OfflineFailure` (marked `TransportFailure`; hooks in snh 1.3+) and repositories pass them through unchanged via `mapBusiness` (or the bare-catch transport guard in Contract B), so offline renders "No internet connection" app-wide. A per-feature "network" class re-narrows that seam and hides the offline copy. (The classification hooks ship in the Supabase entry-point; REST projects get the same pass-through by marking their registry's connectivity failures with the `TransportFailure` mixin — the mixin and `mapBusiness` are transport-agnostic.)

6. **Ship the ARB keys in the same commit as the failure class, named `<feature><FailureName>Title` (and `Subtitle` when used) — `N` failure subclasses means `N` keys (or `2N` if subtitles), not "the obvious one now and TODOs for the rest".** Add to every `.arb` file under `lib/core/localization/arb/`. *Why:* `getTitle(context)` runs at render time against a real locale; without the matching key, users see the constructor's hard-coded English `errorMessage` fallback mid-flow instead of the proper localized string. The deferred-key TODO never lands — there is no second commit. The naming pattern keeps all keys for a hierarchy clustered together in the ARB file and findable from the failure class. Anti-patterns: `slotUnavailable` (no feature prefix — collides with another feature's `SlotUnavailable`), `locationNotFoundError` (the `Error` suffix is noise — every key under this rule is for an error), `locationNotFound` without `Title`/`Subtitle` (ambiguous which one renders where).

7. **Declare per-feature hierarchies `sealed`, not `abstract`.** `sealed class FeatureFailure extends Failure` — the concrete subclasses already live in the same file, so this costs one keyword and makes every `switch` over the hierarchy compile-time exhaustive: adding a new subclass breaks every unhandled `switch` at compile time instead of silently falling through to a fallback at runtime. (The package's base `Failure` stays `abstract` — `sealed` can't cross package boundaries.)

8. **Map `Exception`s, never `Error`s.** Dart `Error` types (`RangeError`, `TypeError`, `StateError`) are programmer bugs — let them crash and fix the code; wrapping them into failures hides defects. Only `Exception` subclasses represent recoverable runtime conditions worth converting to a `Failure`.

## Optional conventions

These aren't rules — projects vary. Pick consistently within your project.

- **Mapper naming — `map<Feature>ErrorCode(String code, {Map<String, dynamic>? payload})`.** `<Feature>` matches the failure hierarchy's noun (so `ItemsFailure` → `mapItemsErrorCode`, `OrganizationsFailure` → `mapOrganizationsErrorCode`) — **not** the RPC verb or action label (no `mapBookSlotErrorCode`, no `mapRedeemItemErrorCode`). Default: one mapper per failure hierarchy. When one hierarchy serves several operation families, each with its own code set, split into per-family mappers — `map<Feature><Family>ErrorCode`, family names still nouns — so every switch stays small and its unknown-fallback tight. Reach for the `rpc:` enum parameter only when family mappers would duplicate a large shared switch — see the multi-RPC mapper pattern in the network skill's `reference.md`.
- **Plain function vs. static method:** Prefer the top-level function — grep-findable as a verb, no ambiguity about which subclass "owns" the mapping. A `FeatureFailure.fromCode(code)` static method is acceptable if the project already uses that style consistently.
- **`with EquatableMixin` on failures:** add it if you'll compare failures in `bloc_test` `expect` matchers or widget tests. Skip otherwise. See [reference.md](reference.md#equatable-yes-or-no).

## Localization

`getTitle(context)` calls `context.localization.<key>` — the project-standard extension over Flutter's gen-l10n. The non-localized `errorMessage` fallback in the constructor keeps the failure usable in pure-Dart tests where no `BuildContext` exists; it is **not** a substitute for the ARB key (see Critical rule 6).

Naming examples — keys for one hierarchy share the `<feature>` prefix so they sort together in the ARB file:

| Failure class | ARB keys |
|---|---|
| `ItemsExpiredFailure` (`ItemsFailure`) | `itemsExpiredTitle`, `itemsExpiredSubtitle` |
| `ItemsSlotUnavailableFailure` (`ItemsFailure`) | `itemsSlotUnavailableTitle`, `itemsSlotUnavailableSubtitle` |
| `OrganizationsNotFoundFailure` (`OrganizationsFailure`) | `organizationsNotFoundTitle` (no subtitle needed) |
| `AppointmentsReschedulingNotAllowedFailure` (`AppointmentsFailure`) | `appointmentsReschedulingNotAllowedTitle`, `appointmentsReschedulingNotAllowedSubtitle` |
| `LocationsNotFoundFailure` (`LocationsFailure`) | `locationsNotFoundTitle` |

Subtitle keys are optional — only add them when the subtitle says more than the title. `getSubtitle` returns `''` (never `null`) when there is no subtitle.

## Templates

- [single_failure.dart](templates/single_failure.dart) — one class, fixed code + message
- [feature_failure.dart](templates/feature_failure.dart) — abstract base + N concrete subclasses + `mapFeatureErrorCode` helper

## Reference

See [reference.md](reference.md) for:
- Localization integration patterns (per project)
- When a failure should carry data (rate limits, conflicts, validation)
- Equatable: yes or no?
- Failures that should NOT auto-snackbar (rate limits, recoverable states)
- Multi-RPC mappers (same code, different meaning per call site)
- Complex payload extraction (when `payload['x']` might be missing or wrong type)
- Common mistakes table

## Checklist

- [ ] **Checked existing features for a reusable failure** before adding a new one (see "First: does the failure already exist?")
- [ ] Picked single vs hierarchy *before* writing the first failure
- [ ] Failure extends `Failure` from the correct `simple_network_handler` entry-point
- [ ] Constructors are `const`
- [ ] `getTitle(context)` returns a localized string when a `BuildContext` is available
- [ ] `getSubtitle(context)` returns a localized string or `''` — never `null`, and never the raw `code` (an error code shown to users is a leak, not a subtitle)
- [ ] **ARB keys added in the same change, named `<feature><FailureName>Title`/`Subtitle`** — every `.arb` file under `lib/core/localization/arb/`. No `Error` suffix, no bare condition names without a feature prefix (see Critical rule 6). Number of keys ≥ number of concrete failure subclasses.
- [ ] **(Hierarchy only)** A `map<Feature>ErrorCode(code)` plain function exists next to the failure file, named after the failure hierarchy's noun (not after an RPC or action verb)
- [ ] **(Hierarchy only)** Base class is `sealed` (subclasses co-located in the same file)
- [ ] **(Hierarchy only)** Exactly one `<Feature>UnknownFailure` fallback — no separate per-feature `*NetworkFailure` and no action-named transport class
- [ ] Failures that should NOT auto-snackbar (rate limits etc.) are documented as such in the class doc comment
