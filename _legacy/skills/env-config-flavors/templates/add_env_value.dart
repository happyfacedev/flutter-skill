// Adding a new env-driven value to EnvConfig — single-file change.
//
// Use when:
//   • The value differs between dev and prod servers
//   • The value is the same for every tenant
//   • The value is read at runtime via a static call on EnvConfig
//
// Do NOT use this template when:
//   • The value differs per organization at runtime → OrganizationConfig
//     (theme, logo, timezone, per-tenant featureFlags)
//   • The value is an app-global runtime-toggleable flag → /bootstrap-composition-root
//     for adding an app-lifetime ExperimentsCubit / RemoteConfigCubit

// ─── In lib/core/config/env_config.dart ─────────────────────────────────────

// ...existing imports + class header...

class EnvConfig {
  // ...existing getters (isDev, isProd, supabaseUrl, ...) elided...

  // STEP 1: Add the new getter as a `switch` over `_current`.
  //
  // The switch is exhaustive over `Environment.dev` / `Environment.prod`, so
  // the compiler tells you if you add a new Environment value later.
  //
  // Pattern: name describes what the value IS, not its env-ness. Good:
  // `analyticsEndpoint`. Bad: `prodAnalyticsEndpoint`, `devOnlyAnalyticsUrl`.

  static String get analyticsEndpoint => switch (_current) {
        Environment.dev => 'https://analytics-dev.example.com',
        Environment.prod => 'https://analytics.example.com',
      };

  // STEP 2 (optional): If the value is a boolean derived from the env, you
  // can compute it inline rather than switch:

  static bool get enableExperimentalFeatures => isDev;

  // STEP 3 (optional): If the value should NOT differ today but is
  // conceptually env-shaped (might differ in the future), declare it as a
  // plain static getter — same shape, single literal — so the switch can be
  // added later without changing call sites:

  static String get marketingSiteUrl => 'https://example.com';
}

// ─── Then in the consumer ───────────────────────────────────────────────────
//
// Wherever the value is needed, read EnvConfig.analyticsEndpoint.
//
//   final endpoint = EnvConfig.analyticsEndpoint;
//   // Use as the base URL for an analytics client, etc.
//
// Do NOT branch on `EnvConfig.isDev` to construct the URL manually — that's
// the exact anti-pattern this skill exists to prevent. The switch lives in
// EnvConfig; consumers stay env-agnostic.

// ─── Verification ────────────────────────────────────────────────────────────
//
// Run both env paths once to confirm:
//   flutter run --dart-define=ENV=dev
//   flutter run --dart-define=ENV=prod
//
// And log or breakpoint the consumer to confirm the right value is in
// effect for each.
