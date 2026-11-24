# Bootstrap & Composition Root — Reference

Source files: `lib/shared_main.dart`, `lib/bootstrapper.dart`, `lib/core/injection/injection.dart`, `lib/core/injection/injection.config.dart` (generated). Authoritative on current registrations; this page is the lookup index.

## App-lifetime singleton roster

The cubits and services that live for the whole app session. Anything not on this list should be `@injectable` (factory), not `@singleton`.

### In `MultiBlocProvider` (UI rebuilds against these)

| Cubit | Lifetime hook | Persistence |
|---|---|---|
| `ThemeCubit` | `create:` (not DI — `AppThemes()` injected at construction) | Hydrated |
| `PermissionsCubit` | `..initialize()` | — |
| `AuthCubit` | (no kick-off; `@postConstruct` does init) | Hydrated |
| `OrganizationCubit` | (no kick-off; hydrates the persisted tenant at construction, publishes to `OrganizationContext`) | Hydrated |
| `ConnectivityCubit` | `..initialize()` | — |
| `LanguageCubit` | (no kick-off) | Hydrated |

### In `MultiRepositoryProvider` (services + non-rebuilt cubits)

| Provider | Source | Notes |
|---|---|---|
| `OrganizationContext` | `getIt` (singleton) | Plain read-only service — current tenant id + timezone for infra layers |
| `PendingNavigationStore` | `getIt` (singleton) | Receives deeplink intents |
| `StartupPipelineSessionCache` | `create:` (not DI) | Per-session memoisation for pipeline gates |
| `StartupPipelineConfig` | `.value` (built pre-`runApp` from `getIt<DefaultStartupSteps>()`) | Assembled at composition time |
| `ForceUpdateCubit` | `getIt` (singleton) | UI doesn't `BlocBuilder` against it; router redirect reads `.state` |
| `IntroSeenCubit` | `getIt` (singleton) | Same — read by router redirect |

When adding a new app-lifetime dependency, decide which provider hosts it using the heuristic in the SKILL.md "Outer vs inner" section.

## Pre-`runApp` initializers — current sequence

`bootstrap()` in `lib/shared_main.dart`. Listed in execution order. Each row notes the prerequisites it depends on.

| Step | Function | Depends on | Why this slot |
|---|---|---|---|
| 1 | `WidgetsFlutterBinding.ensureInitialized()` | — | Required first by Flutter |
| 2 | `EnvConfig.initialize()` | (1) | Reads `String.fromEnvironment('ENV', ...)` |
| 3 | `SystemChrome.setEnabledSystemUIMode(edgeToEdge)` | (1) | UI mode |
| 4 | `SystemChrome.setPreferredOrientations([portraitUp])` | (1) | Orientation lock |
| 5 | **(parallel)** `_setupBloc()` + `_setupSupabase()` + `_setupHive()` | (2) | Read env; independent of each other |
| 6 | `configureDependencies()` | (5) | DI constructs `@singleton`s + `HydratedCubit`s that touch HydratedStorage / Supabase in their constructors |
| 7 | `_buildStartupPipelineConfig()` | (6) | Reads `getIt<DefaultStartupSteps>().defaultOrdered()` |
| 8 | `getIt<DeepLinkService>().initialize()` | (6) | DI ready; must precede `runApp` so cold-start URIs land in `PendingNavigationStore` |
| 9 | `runApp(Bootstrapper(startupPipelineConfig: ...))` | (7), (8) | All prerequisites ready |

`_setupBloc` wires `Bloc.observer = AppBlocObserver()` + builds `HydratedBloc.storage`. `_setupSupabase` calls `Supabase.initialize(...)` + `AppSupabaseErrorRegistry.initialize()`. `_setupHive` calls `Hive.initFlutter()`.

Insertion rule: insert new initializers at the earliest slot whose prerequisites are satisfied. Don't append blindly — appending after step 8 introduces races against the startup pipeline.

## DI annotation decision table

| Annotation | When | Behavior |
|---|---|---|
| `@injectable` (default) | Per-resolve factory — page cubits, repositories, helpers | New instance every `getIt<X>()` |
| `@singleton` | App-lifetime state holder, must be approved | Eager construction at `getIt.init()`; one instance forever |
| `@lazySingleton` | Approved app-lifetime, but may never be needed in some run paths | Constructed on first resolve; same instance after |
| `@singletonAsync` | App-lifetime + async setup required | `getIt.init()` returns `Future<GetIt>`; resolve via `getIt.getAsync<X>()` |
| `@PostConstruct` (on `@singleton`) | Sync registration but needs an init method called automatically | Same effect as `@singletonAsync` from the consumer's point of view (used by `AuthCubit`) |
| `@Environment('dev')` | Dev-only registration (debug tools, mock impls) | Only registered when `getIt.init(environment: 'dev')` |
| Manual `static final` / `getIt.registerSingleton` | **Avoid.** Requires user approval, same rule as `@singleton`. | One-off bypasses DI |

The `@Environment` flag is passed by `configureDependencies()` based on `EnvConfig.isDev`:
```dart
await getIt.init(environment: EnvConfig.isDev ? 'dev' : 'prod');
```

## `BlocProvider.value` carve-out — full list of legal locations

1. **`bootstrapper.dart`** — bridging DI singletons into the bloc tree:
   ```dart
   BlocProvider.value(value: getIt<AuthCubit>()),
   ```
2. **`router.dart` `pageBuilder` callbacks** — sharing a DI singleton across sibling pages:
   ```dart
   pageBuilder: (context, state) => CupertinoPage(
     child: BlocProvider.value(
       value: getIt<SomeCubit>(),
       child: const SomePage(),
     ),
   ),
   ```
3. **Tests** — injecting a mock cubit produced outside the widget tree:
   ```dart
   testWidgets('...', (tester) async {
     await tester.pumpWidget(
       BlocProvider.value(value: mockAuthCubit, child: ...),
     );
   });
   ```

Anywhere else — page widgets, feature cubits, services — use `BlocProvider(create: (_) => getIt<X>())` instead, or accept the dependency via constructor.

## `_SessionResetBridge` listener registry

The full list of listeners currently wired in this widget (for context when adding a new one). Both react to `AuthCubit`:

| Listener | listenWhen predicate | What it does |
|---|---|---|
| `AuthCubit` shell change | `prev.currentShell != curr.currentShell` | On `unauthenticated`: `PendingNavigationStore.reset()` + `OrganizationContext.clearValidated()` + `StartupPipelineSessionCache.clear()` |
| `AuthCubit` user swap | Both `user?.id` non-null AND different | Same per-session reset — guards against future account-switcher flows; filters out the cold-start `null → id` restore so a captured deeplink isn't discarded |

When you add a new listener, follow these conventions:
- `listenWhen` is required (otherwise the listener fires on every state change)
- Cubit-to-cubit calls use `ctx.read<X>()` inside the listener callback (callback context — `read` is legal here)
