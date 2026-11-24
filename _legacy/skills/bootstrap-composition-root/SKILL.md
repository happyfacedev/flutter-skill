---
name: bootstrap-composition-root
description: Works with the single composition root of the app — `lib/shared_main.dart` (the `bootstrap()` pre-`runApp` initialization pipeline) and `lib/bootstrapper.dart` (the global `MultiRepositoryProvider` + `MultiBlocProvider`). Covers the DI carve-out (where `getIt` IS legal vs forbidden), `@injectable` vs `@singleton` vs `@singletonAsync` vs `@Environment('dev')` decisions, the pre-`runApp` initialization sequence and its ordering rules (`EnvConfig.initialize` → storage + Supabase + Hive in parallel → `configureDependencies` → build startup pipeline config → `DeepLinkService.initialize()` → `runApp`), the `Bootstrapper`'s split between `MultiRepositoryProvider` (services + non-rebuilt cubits like `ForceUpdateCubit`/`IntroSeenCubit`) and `MultiBlocProvider` (cubits the UI BlocBuilders against), the `BlocProvider.value` carve-out (composition root + tests only), the `_SessionResetBridge` parent-layer cubit-to-cubit bridge pattern, and adding a new app-lifetime singleton or pre-`runApp` initializer. Use when adding/changing anything in `shared_main.dart` / `bootstrapper.dart` / `lib/core/injection/`, deciding whether a cubit/service is global, debugging "why is getIt complaining about not registered", routing for `runZonedGuarded` error handling, or when the user mentions "bootstrap", "shared_main", "composition root", "getIt", "GetIt", "injection.config.dart", "configureDependencies", "@injectable", "@singleton", "@singletonAsync", "BlocProvider.value", "MultiRepositoryProvider", "global cubit", "app-lifetime", "pre-runApp", "Bootstrapper widget", "runZonedGuarded", "Hive init", or "Supabase.initialize". Cubit shape itself (per-feature internals) → /cubit-creation. Router construction → /navigation-gorouter.
argument-hint: "[component-name]"
---

# Bootstrap & Composition Root

The composition root is the **single physical place** where the app wires its dependencies together. In this project that's two files:

- **`lib/shared_main.dart`** — the `bootstrap()` pre-`runApp` async initialization pipeline (`lib/main.dart` is just `void main() => bootstrap();`)
- **`lib/bootstrapper.dart`** — the global `MultiRepositoryProvider` + `MultiBlocProvider` widget that runs once at startup

Everything outside these two files (plus the per-`BlocProvider create:` callback) is forbidden from calling `getIt` directly. That's the rule. The carve-out is narrow because composition is the one place we accept the trade-off of opaque dependencies — everywhere else, dependencies arrive via the constructor so they show up in tests and refactors.

This skill answers: "where does my new service initialize?", "should this be `@singleton` or `@injectable`?", "where does this provider go in `Bootstrapper` — top or bottom?", "why is `BlocProvider.value` allowed here?", and "what ordering rules do I have to follow when adding a pre-`runApp` step?".

## Critical Rules (Never Break)

1. **`getIt` is legal in exactly two locations.** Inside `shared_main.dart` / `bootstrapper.dart` (the composition root), and inside a `BlocProvider` / `RepositoryProvider` / route `pageBuilder` `create:` (or `value:`) callback. *Why:* freeform `getIt` calls hide dependencies, break testability, bypass constructor injection, and create circular-init bugs where two services reach for each other during construction. Inside a feature's cubit, repository, widget — use constructor injection.

2. **`@singleton` requires explicit user approval.** Default is `@injectable` (factory — fresh instance per resolution). *Why:* singletons hold state for the app's lifetime — their blast radius is wide and their lifecycle is invisible. They must be a deliberate decision, not a "well, I only need one of them" shortcut. The same rule applies to `@lazySingleton`, manual `static final` instances, and `getIt.registerSingleton`.

3. **`BlocProvider.value` / `RepositoryProvider.value` are legal only in the composition root (`bootstrapper.dart` and `pageBuilder` callbacks in `router.dart`) and tests.** *Why:* `.value` aliases an externally-owned instance into the widget tree — that's almost always a singleton being bridged from DI, which only makes sense once at the composition layer. Elsewhere it leaks lifecycle ownership: a child widget can't tell who is responsible for disposing the cubit, and naive callers will pop the page and stop the cubit prematurely.

4. **Pre-`runApp` ordering is load-bearing.** Some steps depend on others having finished. `EnvConfig.initialize()` must precede anything reading env (Supabase URL/key). Supabase + storage (HydratedStorage) + Hive must precede `configureDependencies()` because DI instantiates `@singleton` repositories that touch Supabase and `HydratedCubit`s (`AuthCubit`, `OrganizationCubit`, `ThemeCubit`, `LanguageCubit`) that read persisted state at construction. **`DeepLinkService.initialize()` MUST run before `runApp`** so cold-start URIs are captured into `PendingNavigationStore` before the pipeline can navigate away. Adding a new step means picking the right slot in this order, not just appending.

5. **The `Bootstrapper` widget owns provider hierarchy, NOT business logic.** No cubit-to-cubit calls in the `Bootstrapper` build method itself. The `_SessionResetBridge` `StatelessWidget` exists specifically to host parent-layer `BlocListener`s that bridge auth → infra reset (clear `PendingNavigationStore`, `OrganizationContext`, `StartupPipelineSessionCache` on logout / user-swap) — that's the only legitimate cubit-to-cubit signalling in the composition root, and it's encapsulated in one named widget. Don't add more bridges to `Bootstrapper`'s direct children; if you need another auth-driven side effect, add a `BlocListener` inside the bridge widget.

6. **`MultiRepositoryProvider` vs `MultiBlocProvider` is not arbitrary.** The outer `MultiRepositoryProvider` holds: (a) plain services (`OrganizationContext`, `PendingNavigationStore`, `StartupPipelineSessionCache`) and config (`StartupPipelineConfig`), and (b) cubits the UI does NOT `BlocBuilder` against (`ForceUpdateCubit`, `IntroSeenCubit` — consumed once by the router redirect). The inner `MultiBlocProvider` holds cubits the UI actually rebuilds against. Putting a non-rebuilt cubit in `MultiBlocProvider` is wasteful (every emit triggers `BlocBuilder` lookups); putting a rebuilt-against cubit in `MultiRepositoryProvider` means `context.read<X>()` works but `BlocBuilder<X, ...>` won't subscribe.

## The pre-`runApp` pipeline

`bootstrap()` in `shared_main.dart` is the single entry point (`lib/main.dart` is `void main() => bootstrap();`). The current sequence — in order — is:

```
runZonedGuarded(() async {
  WidgetsFlutterBinding.ensureInitialized();
  EnvConfig.initialize();                         // ENV (dart-define)
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await SystemChrome.setPreferredOrientations([portraitUp]);

  // Independent — fanned out in parallel:
  await Future.wait([
    _setupBloc(),       // Bloc.observer = AppBlocObserver + HydratedStorage.build
    _setupSupabase(),   // Supabase.initialize + AppSupabaseErrorRegistry.initialize
    _setupHive(),       // Hive.initFlutter
  ]);

  await configureDependencies();                   // DI — getIt.init(env: ...)
  final startupPipelineConfig = await _buildStartupPipelineConfig();
  await getIt<DeepLinkService>().initialize();     // capture cold-start URIs
  runApp(Bootstrapper(startupPipelineConfig: startupPipelineConfig));
}, (error, stackTrace) { /* global Failure → snackbar; else log */ });
```

### Ordering rules each step satisfies

| Step | Must come after | Reason |
|---|---|---|
| `EnvConfig.initialize` | (first) | Everything else reads env (Supabase URL, key, deep-link host) |
| `_setupBloc` / `_setupSupabase` / `_setupHive` | `EnvConfig` | They read env vars; independent of each other so they run in parallel |
| `configureDependencies` | Storage + Supabase + Hive | `@singleton` cubits constructed during DI touch HydratedStorage (`AuthCubit`, `OrganizationCubit`, …) and Supabase in their constructors |
| `_buildStartupPipelineConfig` | DI | Reads `getIt<DefaultStartupSteps>().defaultOrdered()` |
| `DeepLinkService.initialize` | DI | But must precede `runApp` so cold-start URIs are captured before the pipeline page mounts |
| `runApp` | (last) | All prerequisites ready |

When adding a new step, identify which prerequisites it has (env? DI? a specific singleton?) and insert at the earliest slot that satisfies them. Don't append blindly — appending after `DeepLinkService.initialize` introduces races where the pipeline could complete before your initializer runs.

### Global error capture

The whole pipeline runs inside `runZonedGuarded(..., (error, stackTrace) { ... })`. Any uncaught error in the zone surfaces here. The handler distinguishes:

- **`Failure`** (typed domain failure) → show a snackbar via `rootNavigatorKey.currentContext`'s `ScaffoldMessenger` if a context is available
- **Anything else** → `log()` the error + stack trace

Don't add try/catch around individual pipeline steps unless you need step-specific recovery — the zone catches everything.

## The `Bootstrapper` widget — outer vs inner

```dart
MultiRepositoryProvider(
  providers: [
    RepositoryProvider.value(value: getIt<OrganizationContext>()),
    RepositoryProvider.value(value: getIt<PendingNavigationStore>()),
    RepositoryProvider<StartupPipelineSessionCache>(
      create: (_) => StartupPipelineSessionCache(),
    ),
    RepositoryProvider.value(value: startupPipelineConfig),
    // Non-rebuilt cubits — router redirect reads them via .state, but no
    // widget does BlocBuilder<ForceUpdateCubit, ...>.
    RepositoryProvider.value(value: getIt<ForceUpdateCubit>()),
    RepositoryProvider.value(value: getIt<IntroSeenCubit>()),
  ],
  child: MultiBlocProvider(
    providers: [
      BlocProvider(create: (_) => ThemeCubit(AppThemes())),
      BlocProvider.value(value: getIt<PermissionsCubit>()..initialize()),
      BlocProvider.value(value: getIt<AuthCubit>()),
      BlocProvider.value(value: getIt<OrganizationCubit>()),
      BlocProvider.value(value: getIt<ConnectivityCubit>()..initialize()),
      BlocProvider.value(value: getIt<LanguageCubit>()),
    ],
    child: const PermissionLifecycleWrapper(
      child: _SessionResetBridge(child: App()),
    ),
  ),
)
```

### Which provider hosts which kind of dependency

| Goes in **MultiRepositoryProvider** | Goes in **MultiBlocProvider** |
|---|---|
| Plain services (`OrganizationContext`, `PendingNavigationStore`, `StartupPipelineSessionCache`) | Cubits the UI rebuilds against (`ThemeCubit`, `AuthCubit`, `OrganizationCubit`, `PermissionsCubit`, `ConnectivityCubit`, `LanguageCubit`) |
| Plain config objects (`StartupPipelineConfig`) | — |
| Cubits the router redirect reads but UI doesn't `BlocBuilder` against (`ForceUpdateCubit`, `IntroSeenCubit`) | — |

The `..initialize()` cascade on `PermissionsCubit` and `ConnectivityCubit` is the standard kick-off — these cubits register subscriptions or do initial loads. `AuthCubit`, `OrganizationCubit`, `ThemeCubit`, and `LanguageCubit` are `HydratedCubit`s that restore their persisted state at construction, so they need no kick-off cascade (`AuthCubit` runs its session check via `@postConstruct`).

### Why `BlocProvider.value` here vs `BlocProvider(create:)`

Every cubit in `MultiBlocProvider` (except `ThemeCubit`) uses `.value` because the DI singleton is the canonical instance — the widget tree is just bridging it in. `ThemeCubit` uses `create:` because its `AppThemes()` constructor arg is built fresh per app launch, not via DI. This is the documented carve-out: the composition root is the legitimate place for `.value` to alias DI-owned instances.

## The `_SessionResetBridge` pattern

The `Bootstrapper` widget's leaf is `_SessionResetBridge`, a `StatelessWidget` that hosts `BlocListener`s in a `MultiBlocListener`. These bridges are the project's pattern for cubit-to-cubit signalling **without violating the no-cubit-to-cubit rule** — the bridge is a parent widget reacting to `AuthCubit`, not a cubit injecting another cubit.

Listeners currently in this widget (both react to `AuthCubit`):
- **Shell → unauthenticated (logout):** `listenWhen: prev.currentShell != curr.currentShell`; when the shell becomes `unauthenticated`, clear per-session infra state — `PendingNavigationStore.reset()`, `OrganizationContext.clearValidated()`, `StartupPipelineSessionCache.clear()`.
- **User swap:** `listenWhen` fires only when both `prev.user?.id` and `curr.user?.id` are non-null AND different (filters out the cold-start `null → id` session-restore transition so a captured cold-start deeplink isn't discarded); runs the same reset. No flow swaps users today, but the bridge guards against future ones.

Adding a new auth-driven side effect: prefer adding a `BlocListener` inside the existing `MultiBlocListener` of `_SessionResetBridge` over creating a sibling bridge widget. The single-widget pattern keeps cubit-to-cubit signalling traceable. Each listener uses a `listenWhen` predicate and does its cubit-to-cubit calls via `ctx.read<X>()` inside the listener callback (callback context — `read` is legal there).

## Adding a new app-lifetime singleton (workflow)

**Step 0. Get explicit user approval** that singleton lifetime is justified. Default answer is `@injectable`. Singletons are for: app-lifetime state holders, long-lived stream subscriptions that must survive page navigation, `HydratedCubit`s that own persistence, services the router redirect or composition root needs synchronously.

**Step 1. Annotate.** Pick one:
- `@singleton` — eager construction at DI init (default for app-lifetime cubits)
- `@lazySingleton` — first-resolve construction (use for app-lifetime services that may never be needed in some run paths, e.g., a debug-only tool)
- `@singletonAsync` (or `@PostConstruct` on a `@singleton`) — for services that need async setup before they're usable; `getIt.init()` returns `Future<GetIt>` when any of these are registered
- `@Environment('dev')` — combine with the above to scope registration to dev builds only

**Step 2. Rebuild DI.** `dart run build_runner build --delete-conflicting-outputs` regenerates `injection.config.dart`. → `/code-generation-workflow` for the full workflow and recovery steps.

**Step 3. Provider entry.** Add to `Bootstrapper`'s `MultiRepositoryProvider` OR `MultiBlocProvider` per the table above. Use `.value` (it's the composition root). Add a `..initialize()` cascade if the cubit needs a kick-off call.

**Step 4. (If pre-`runApp` init needed)** Add `getIt<XService>().initialize()` to `shared_main.dart` in the correct ordering slot — usually right after `configureDependencies` (basic singletons) or right before `runApp` (cold-state captures like `DeepLinkService`).

See [`templates/add_global_cubit.dart`](templates/add_global_cubit.dart) for a fill-in scaffold.

## Adding a pre-`runApp` initializer (workflow)

**Step 1. Identify dependencies.** What needs to be ready before this runs? Env? DI? A specific singleton? Another initializer?

**Step 2. Pick the slot.** Insert in `shared_main.dart` between the latest prerequisite and any consumer. If unsure, add a comment naming the prerequisites — future-you will thank present-you.

**Step 3. Await or fire-and-forget?** Await anything the first widget will read (e.g., the cold-start deeplink capture). Fire-and-forget anything the app degrades gracefully without. Errors in unawaited futures still surface via `runZonedGuarded`.

**Step 4. Document the why** in a comment. The current pipeline has rich comments for non-obvious orderings (e.g., "Storage + Supabase must be ready before DI wires HydratedCubits") — match that pattern.

See [`templates/add_pre_runapp_init.dart`](templates/add_pre_runapp_init.dart) for a fill-in scaffold.

## What this skill does NOT cover

- **Cubit shape** (state class, `BlocStatus`, `copyWith`, streaming cubits) → `/cubit-creation`. This skill covers WHERE a cubit is registered globally; how it's structured is the cubit-creation skill's job.
- **Router construction itself** (the router factory, routes, redirect logic) → `/navigation-gorouter`. The router consumes some of the cubits this skill registers but it isn't part of the composition root proper.
- **Environment switching** (the `EnvConfig` dev/prod axis + the `OrganizationConfig` per-tenant axis, adding new env values) → `/env-config-flavors`. `EnvConfig.initialize()` is one of the pre-`runApp` steps documented above; the full env / organization-config model lives in that skill.
- **Deep-link pipeline** consumed by `DeepLinkService.initialize()` (one of the pre-`runApp` steps) → `/deep-link-handling`.
- **`AuthCubit`'s shape and event mapping** (the cubit's `@singleton` registration belongs here; the *internals* of how it maps Supabase events to state) → `/auth-flow-supabase`.

## Templates

- [`templates/add_global_cubit.dart`](templates/add_global_cubit.dart) — annotate `@singleton`, rebuild DI, add to `Bootstrapper`, wire any pre-runApp init
- [`templates/add_pre_runapp_init.dart`](templates/add_pre_runapp_init.dart) — `getIt<XService>().initialize()` pattern with ordering note

## Reference

See [reference.md](reference.md) for:
- The current app-lifetime singleton roster (which cubits live globally, which providers host them)
- The current pre-`runApp` initializer list with their dependencies
- The `@injectable` vs `@singleton` vs `@lazySingleton` vs `@singletonAsync` vs `@Environment` decision table
- The `BlocProvider.value` carve-out locations (full list)

## Checklist

- [ ] If a new app-lifetime singleton: explicit user approval obtained for `@singleton`
- [ ] DI annotation matches the lifecycle need (`@injectable` for per-resolve, `@singleton` for eager app-lifetime, `@lazySingleton` for cold-path, `@singletonAsync` / `@PostConstruct` for async setup, `@Environment('dev')` for dev-only)
- [ ] `dart run build_runner build --delete-conflicting-outputs` rerun after annotation changes
- [ ] Provider added to the correct half of `Bootstrapper`: `MultiRepositoryProvider` for services + non-rebuilt cubits, `MultiBlocProvider` for cubits the UI `BlocBuilder`s against
- [ ] `BlocProvider.value` used (not `create:`) when bridging from DI — composition-root carve-out
- [ ] `..initialize()` cascade added if the cubit / service has an init step
- [ ] If pre-`runApp` init needed: inserted in `shared_main.dart` in the correct ordering slot, with a comment naming prerequisites
- [ ] No `getIt` call added outside the composition root or a `BlocProvider/RepositoryProvider create:`/`value:` callback
- [ ] No new bridge widget at the `Bootstrapper` level — new cubit-to-cubit signals go inside `_SessionResetBridge`'s `MultiBlocListener`
