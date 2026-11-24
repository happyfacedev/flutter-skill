---
name: env-config-flavors
description: Two-layer runtime/build configuration — `EnvConfig` (dev vs prod servers, selected at compile time via `--dart-define=ENV=`) and `OrganizationConfig` (per-tenant visual theme + feature flags, loaded at runtime once an organization is selected). Covers adding a new env-driven value (extending `EnvConfig`'s `switch` over `Environment`), the `dart-define=ENV=dev|prod` invocation contract, when a value belongs on `EnvConfig` (dev/prod axis) vs `OrganizationConfig` (per-tenant runtime axis), the single `lib/main.dart` → `bootstrap()` entry point, and how `OrganizationConfig` hydrates per-tenant theming. Use when adding a new dev/prod-differentiated value (Supabase URL, deep-link host, callback URL, feature flag), wiring per-tenant theming, debugging "wrong URL used" / "feature flag not honored", deciding which of the two config classes a value belongs in, or when the user mentions "EnvConfig", "OrganizationConfig", "env config", "dart-define", "ENV=dev", "ENV=prod", "entry point", "deepLinkHost", "customScheme", "per-tenant theme", "feature flag", or "dev vs prod". The env file is `lib/core/config/env_config.dart`; the tenant config is `lib/core/config/organization_config.dart`. DI registration → /bootstrap-composition-root. The dev-only routes that read `EnvConfig.isDev` → /navigation-gorouter.
argument-hint: "[config-key]"
---

# Env / Organization Configuration

The boilerplate has **two config classes** answering two different "which X am I" questions:

| Class | File | Question | Axis |
|---|---|---|---|
| **`EnvConfig`** | `lib/core/config/env_config.dart` | "Which servers am I talking to?" | dev / prod (compile-time, `--dart-define=ENV=`) |
| **`OrganizationConfig`** | `lib/core/config/organization_config.dart` | "Which TENANT's colors/logo/flags do I show?" | per-organization (runtime) |

The mental model: a single Dart codebase, one entry point (`lib/main.dart` → `bootstrap()`), compiles into one app that runs against either the dev or the prod backend (`EnvConfig`), and at runtime themes itself for whichever organization the user selected (`OrganizationConfig`). There is no per-brand build, no flavor matrix, and no entry-point-per-app layer — `EnvConfig` is the only compile-time axis.

## Critical Rules (Never Break)

1. **`EnvConfig.initialize()` MUST run before any consumer reads env values.** *Why:* `_current` is `late` — accessing `EnvConfig.supabaseUrl` before init throws `LateInitializationError`. `bootstrap()` in `shared_main.dart` calls it first thing; if you add a step that reads env, ensure it runs after that. See `/bootstrap-composition-root` for the canonical ordering.

2. **NEVER hardcode dev/prod URLs or keys outside `EnvConfig`.** *Why:* a literal Supabase URL in a repository quietly bypasses the env switch — and the next "deploy to prod" turns into a hunt for stragglers. Anything that differs between dev and prod is a getter on `EnvConfig`, period.

3. **NEVER put per-tenant differentiation on `EnvConfig`.** *Why:* `EnvConfig` is environment-axis only (compile-time, server selection). Per-tenant values — theme seed color, logo URL, organization name, timezone, per-tenant feature flags — live on `OrganizationConfig` because the tenant is a runtime selection, not a compile-time flag. Mixing axes here produces values like `EnvConfig.organizationPrimaryColor` — exactly the wrong shape.

4. **There is ONE entry point: `lib/main.dart` calls `bootstrap()`.** *Why:* the boilerplate is a single app, not a brand container. `main()` is just `void main() => bootstrap();`. Don't add alternate entry-point files to select a build variant — the only build variant is the `ENV` dart-define, and it does not need its own entry file.

5. **NEVER read `EnvConfig.isDev` or `EnvConfig.isProd` inside business logic.** *Why:* the test for "what should I do here?" is almost always feature-flag-shaped, not environment-shaped. Reading `isDev` directly couples the feature to the env axis instead of letting `EnvConfig` expose a named flag (`enableDebugLogging`). The legitimate exception: gating dev-only debug routes in `router.dart` (`if (EnvConfig.isDev && !kReleaseMode) GoRoute(...)`).

6. **`OrganizationConfig` is loaded/hydrated at runtime, never compiled in.** *Why:* the selected tenant comes from the user's choice and is persisted by `OrganizationCubit` (a `HydratedCubit`). Don't bake a specific organization id or color into the source — the config is built from the backend response (`OrganizationConfig.fromJson`) or a seed color (`OrganizationConfig.fromSeedColor`) at runtime.

## Decision: which config does this value belong in?

Run the value through two questions in order:

**Q1: Does it differ between dev and prod servers (and is it the same for every tenant)?**
- Yes → `EnvConfig` (Supabase URL, Supabase anon key, auth callback URL, deep-link host, custom scheme, debug-logging toggle)
- No → Q2

**Q2: Does it differ per organization at runtime?**
- Yes → `OrganizationConfig` (theme — primary/seed color, logo URL, organization name; timezone; per-tenant feature flags; loaded from the API once the user picks an organization)
- No → it's not config; put it where the value is used.

## `EnvConfig` — current shape

```dart
enum Environment { dev, prod }

class EnvConfig {
  EnvConfig._();
  static late Environment _current;

  static void initialize() {
    const envString = String.fromEnvironment('ENV', defaultValue: 'dev');
    _current = envString == 'prod' ? Environment.prod : Environment.dev;
  }

  static Environment get current => _current;
  static bool get isDev => _current == Environment.dev;
  static bool get isProd => _current == Environment.prod;

  // Switch-over-env values (replace placeholders with your project's values):
  static String get supabaseUrl => switch (_current) {
        Environment.dev => 'https://YOUR-DEV-PROJECT.supabase.co',
        Environment.prod => 'https://YOUR-PROD-PROJECT.supabase.co',
      };
  static String get supabaseAnonKey => switch (_current) {
        Environment.dev => 'YOUR_DEV_SUPABASE_ANON_KEY',
        Environment.prod => 'YOUR_PROD_SUPABASE_ANON_KEY',
      };

  // True once Supabase has real credentials (boot still succeeds with
  // placeholders so the app reaches the landing screen).
  static bool get isSupabaseConfigured =>
      !supabaseUrl.contains('YOUR-') && !supabaseAnonKey.startsWith('YOUR_');

  // Auth + deep-link config (consumed by the auth flow + DeepLinkParser):
  static String get authCallbackUrl => 'https://app.example.com/auth/callback';
  static String get deepLinkHost => 'app.example.com';
  static String get customScheme => 'boilerplate';

  // Feature flags computed from the env:
  static bool get enableDebugLogging => isDev;
}
```

Adding a new env value: add a getter that switches over `_current` (or a constant / computed flag if it doesn't vary by env yet but is conceptually env-shaped). See [`templates/add_env_value.dart`](templates/add_env_value.dart).

## `OrganizationConfig` — current shape

`OrganizationConfig` (an `Equatable`) is the runtime, per-tenant configuration. It carries:

- **Identity** — `organizationId`, `organizationName`
- **Theme** — `lightTheme`, `darkTheme` (`ThemeData`, built from a seed color), `logoUrl`
- **Scheduling** — `timezone` (IANA, e.g. `Europe/Bucharest`; nullable when the source RPC doesn't return it)
- **Feature flags** — `featureFlags` (`Map<String, bool>`) + `isFeatureEnabled(key, {defaultValue})`

Constructors:
- `OrganizationConfig.fromJson(json)` — builds the themes from a `seed_color` hex; used when hydrating from the backend response.
- `OrganizationConfig.fromSeedColor({organizationId, organizationName, seedColor, ...})` — convenience constructor.
- `toJson()` — persists identity + flags + the extracted seed color (themes are rebuilt from the seed, not serialized).

`OrganizationConfig` is **selected and persisted at runtime** by `OrganizationCubit` (a `HydratedCubit` — see `/bootstrap-composition-root` for its singleton slot). The cubit publishes the active organization id + timezone into `OrganizationContext` (in `lib/core/services/organization_context.dart`) so infra-layer consumers (repositories) can read the current tenant without depending on the cubit. Per-tenant theming flows from the selected `OrganizationConfig` into `MaterialApp`'s `theme` / `darkTheme`.

This skill covers the *shape* of `OrganizationConfig`; the runtime selection flow (search/select an organization, hydrate, reconcile against the organizations the user belongs to) is feature work under `lib/core/organization/`.

## Build invocation contract

One entry point, one compile-time axis (`ENV`):

```bash
# Dev (default ENV when omitted is `dev`)
flutter run --dart-define=ENV=dev

# Prod build
flutter build apk --dart-define=ENV=prod --release

# Quick local dev — ENV defaults to dev
flutter run
```

`lib/main.dart` is `void main() => bootstrap();` (see `lib/shared_main.dart`). There are no flavors and no per-brand entry points to pass; `ENV` is the only knob.

## Adding a new env-driven value (the procedure)

Most common change. Three steps:

1. **Add the getter to `EnvConfig`** with a `switch (_current)` over `Environment.dev` / `Environment.prod` cases (or a computed flag for env-derived booleans).
2. **Update consumers** to read `EnvConfig.foo` instead of any hardcoded value.
3. **Verify** by running once each with `--dart-define=ENV=dev` and `--dart-define=ENV=prod` — confirm the right value is in effect.

See [`templates/add_env_value.dart`](templates/add_env_value.dart) for the scaffold.

If the value should be a runtime-toggleable feature flag rather than env-driven, it likely belongs on `OrganizationConfig.featureFlags` (per-tenant) or, if it's app-global runtime state, in a dedicated app-lifetime cubit (see `/bootstrap-composition-root` for adding a global cubit).

## What this skill does NOT cover

- **`OrganizationConfig` runtime hydration + reconciliation** (selecting an organization, persisting it via `OrganizationCubit`, reconciling the persisted id against the organizations the user belongs to) — that's feature code under `lib/core/organization/`. This skill covers the *shape* of `OrganizationConfig`, not the selection flow.
- **The startup pipeline** that consumes the resolved organization → `/bootstrap-composition-root` covers `StartupPipelineConfig` wiring; the pipeline cubit itself lives under `lib/core/startup/`.
- **Deep-link host + custom scheme** are *declared* on `EnvConfig` (`deepLinkHost` / `customScheme`) but *consumed* by `DeepLinkService` / `DeepLinkParser`. See `/deep-link-handling` for the consumer side.
- **Native build files** — `build.gradle.kts`, `Info.plist`, Xcode config — are standard Flutter setup and out of scope.

## Templates

- [`templates/add_env_value.dart`](templates/add_env_value.dart) — adding a new dev/prod-differentiated value to `EnvConfig` (one getter per env-axis decision)

## Reference

See [reference.md](reference.md) for:
- The full `EnvConfig` getter list with the dev/prod values and where each is consumed
- The full `OrganizationConfig` field/constructor surface
- The env-axis (compile-time) vs tenant-axis (runtime) split, illustrated
- Common mistakes (mixing axes, hardcoding URLs, baking in a tenant)

## Checklist

- [ ] Identified the right config class via the two-question decision tree (dev/prod axis → `EnvConfig`; per-tenant runtime → `OrganizationConfig`)
- [ ] If adding to `EnvConfig`: new value is a `static` getter with a `switch (_current)` over `Environment.dev` / `Environment.prod` (or a computed flag)
- [ ] If adding to `OrganizationConfig`: declared as a field with a sensible default, threaded through `fromJson` / `toJson` if it must persist
- [ ] `EnvConfig.initialize()` is the first step of any code path that reads env values (already the case in `shared_main.dart`)
- [ ] No hardcoded dev/prod URL / key outside `EnvConfig`
- [ ] No `EnvConfig.isDev` / `EnvConfig.isProd` checks inside business logic — those are dev-route gates only
- [ ] No baked-in organization id / color in source — `OrganizationConfig` is built at runtime
- [ ] Verified both `--dart-define=ENV=dev` and `--dart-define=ENV=prod` paths
