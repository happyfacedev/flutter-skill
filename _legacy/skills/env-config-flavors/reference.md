# Env / Organization Config — Reference

Lookup index for `lib/core/config/`. Two config classes: `EnvConfig` (compile-time dev/prod axis) and `OrganizationConfig` (runtime per-tenant axis).

## `EnvConfig` — full getter list

Source: `lib/core/config/env_config.dart`.

| Getter | Returns | dev | prod |
|---|---|---|---|
| `Environment current` | enum | — | — |
| `bool isDev` | true on dev | ✓ | — |
| `bool isProd` | true on prod | — | ✓ |
| `String supabaseUrl` | Supabase project URL | (your dev project) | (your prod project) |
| `String supabaseAnonKey` | Anon key JWT | (your dev key) | (your prod key) |
| `bool isSupabaseConfigured` | true once placeholders replaced | derived | derived |
| `String authCallbackUrl` | Universal-link auth callback | `https://app.example.com/auth/callback` | (same) |
| `String deepLinkHost` | Universal-link domain | `app.example.com` | (same) |
| `String customScheme` | Custom URL scheme | `boilerplate` | (same) |
| `bool enableDebugLogging` | Log Supabase calls | `true` (== isDev) | `false` |

The Supabase URL/key ship as `YOUR-...` placeholders; `bootstrap()` still calls `Supabase.initialize` so the app boots to the landing screen, and `isSupabaseConfigured` reports whether real credentials are in place.

## `OrganizationConfig` — field + constructor surface

Source: `lib/core/config/organization_config.dart`. An `Equatable` runtime value object — the per-tenant theme/identity/flags.

| Member | Type | Purpose |
|---|---|---|
| `organizationId` | `String` | Unique tenant id |
| `organizationName` | `String` | Display name |
| `lightTheme` | `ThemeData` | Built from a seed color (`ColorScheme.fromSeed`, Material 3) |
| `darkTheme` | `ThemeData?` | Optional dark variant |
| `logoUrl` | `String?` | Tenant logo |
| `timezone` | `String?` | IANA zone (e.g. `Europe/Bucharest`); nullable when the source RPC omits it |
| `featureFlags` | `Map<String, bool>` | Per-tenant flags |
| `isFeatureEnabled(key, {defaultValue=true})` | `bool` | Flag lookup with default |

| Constructor / method | Use |
|---|---|
| `OrganizationConfig.fromJson(json)` | Build from backend response; reads `seed_color` hex (defaults to `#42A5F5`) and constructs light + dark themes |
| `OrganizationConfig.fromSeedColor({...})` | Convenience constructor from a `Color` |
| `toJson()` | Persist identity + flags + extracted seed color (themes are NOT serialized — rebuilt from the seed) |

Selected + persisted at runtime by `OrganizationCubit` (`HydratedCubit`); the active tenant id + timezone are published into `OrganizationContext` (`lib/core/services/organization_context.dart`) for infra-layer consumers.

## Where each `EnvConfig` value is consumed

So changing one is traceable:

| Getter | Consumer file | What it does |
|---|---|---|
| `supabaseUrl`, `supabaseAnonKey`, `enableDebugLogging` | `lib/shared_main.dart` (`_setupSupabase`) | `Supabase.initialize(url:, anonKey:, debug:)` |
| `authCallbackUrl` | `lib/core/auth/` flows | Email-confirmation + password-reset callback target |
| `deepLinkHost`, `customScheme` | `lib/core/navigation/services/deep_link_service.dart` | Passed to `DeepLinkParser.parse(validHost:, validScheme:)` |
| `isDev` | `lib/core/router/router.dart` | Gates dev-only routes behind `if (EnvConfig.isDev && !kReleaseMode)` |

## The two axes

| | Compile-time | Runtime |
|---|---|---|
| **Class** | `EnvConfig` | `OrganizationConfig` |
| **Selected by** | `--dart-define=ENV=dev\|prod` | the user picking an organization |
| **Changes** | only by rebuilding | any time during a session |
| **Same for every tenant?** | yes | no — that's the point |
| **Holds** | server URLs, keys, callback/deep-link host, debug flag | theme, logo, name, timezone, per-tenant flags |

## Common mistakes

| Mistake | Why it bites | Fix |
|---|---|---|
| Hardcoding a Supabase URL in a repository | The next env switch leaves a straggler talking to the wrong project | Read `EnvConfig.supabaseUrl` |
| Adding `EnvConfig.organizationPrimaryColor` | Mixes env axis (dev/prod) with tenant axis (per-org runtime) | Move to `OrganizationConfig` |
| Baking an organization id / seed color into source | Tenant is a runtime choice, not a build constant | Build `OrganizationConfig` via `fromJson` / `fromSeedColor` at runtime |
| Reading `EnvConfig.isProd` inside feature code | Couples the feature to the env axis | Add a named flag on `EnvConfig` (`enableX`) and read that, or use a per-tenant `featureFlags` entry |
| Adding an alternate entry-point file to pick a variant | The only build variant is `ENV`; alternate entries are dead weight | Keep `lib/main.dart` → `bootstrap()`; pass `--dart-define=ENV=` |

## Quick command reference

```bash
# Dev (fastest — ENV defaults to dev)
flutter run

# Dev, explicit env
flutter run --dart-define=ENV=dev

# Prod build
flutter build apk --dart-define=ENV=prod --release
```
