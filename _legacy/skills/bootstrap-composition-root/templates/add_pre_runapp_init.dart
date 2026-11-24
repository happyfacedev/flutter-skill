// Adding a new pre-runApp initializer.
//
// Pre-runApp initializers do work that MUST happen before the first widget
// mounts. Examples already in the pipeline:
//
//   EnvConfig.initialize()                            — must precede anything reading env
//   _setupBloc / _setupSupabase / _setupHive          — storage backends (run in parallel)
//   configureDependencies()                           — DI itself
//   _buildStartupPipelineConfig()                     — reads getIt<DefaultStartupSteps>()
//   getIt<DeepLinkService>().initialize()             — capture cold-start URIs
//
// When you add a new step, the questions are:
//   1. What does it depend on?         → determines the slot
//   2. Do I await or fire-and-forget?  → does the first widget need the result?
//   3. Why is this slot the right one? → comment for future-you

// ─── Example: adding an experiments fetcher before runApp ────────────────────
//
// Goal: pre-fetch feature flags so the first frame doesn't render the
// pre-experiment UI then flicker into post-experiment UI.
//
// Dependencies: configureDependencies (need getIt), Supabase (the fetch goes
// through a Supabase RPC).
// Decision: await (the first widget reads ExperimentsCubit.state to decide
// which UI variant to render — must be ready before runApp).
// Slot: right after configureDependencies — DI is ready, Supabase is ready,
// no other initializer depends on experiments.

// In lib/shared_main.dart, the sequence becomes:
//
//   await configureDependencies();
//   await _fetchInitialExperiments();           // <-- new step here
//   final startupPipelineConfig = await _buildStartupPipelineConfig();
//   await getIt<DeepLinkService>().initialize();
//   runApp(Bootstrapper(startupPipelineConfig: startupPipelineConfig));
//
// /// Fetches initial experiment flags so the first frame renders the correct
// /// UI variant. Awaited because the first widget reads
// /// `ExperimentsCubit.state.flags` synchronously. Depends on
// /// configureDependencies (for getIt) and _setupSupabase (the fetch uses
// /// the Supabase client). Safe to await — the typical fetch is under 200ms
// /// against the cache, and the splash screen renders during the wait
// /// regardless.
// Future<void> _fetchInitialExperiments() async {
//   await getIt<ExperimentsCubit>().fetchInitialFlags();
// }

// ─── When to fire-and-forget instead ─────────────────────────────────────────
//
// If the first widget doesn't strictly need the result and the app degrades
// gracefully without it, fire-and-forget by NOT awaiting (and add the
// `// ignore: discarded_futures` comment so the analyzer doesn't complain).
//
// Example: telemetry handshake — app works fine if it lands during runApp
// instead of before:
//
//   // ignore: discarded_futures
//   getIt<TelemetryService>().handshake();
//
// Errors in unawaited futures still surface via runZonedGuarded's handler,
// so this is not silently dropping failures — just not blocking startup.

// ─── Ordering pitfalls to avoid ──────────────────────────────────────────────
//
// 1. Appending after DeepLinkService.initialize:
//    The startup pipeline can run before your init completes, which races
//    against the cold-start dispatch. Don't do this unless your init is
//    explicitly post-runApp work.
//
// 2. Putting work before configureDependencies that calls getIt<X>():
//    DI isn't ready — getIt throws. If you need a service before DI, either
//    construct it manually (like CrashReporter is) or move it after DI.
//
// 3. Putting Supabase-touching work before _setupSupabase:
//    Supabase.instance throws if not initialized. Same for Hive.
//
// 4. Not documenting WHY the slot is correct:
//    Future maintainers will reorder steps to "tidy them up" and break the
//    ordering. Add a comment naming the prerequisites explicitly.
