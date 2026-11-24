---
name: widgetbook-catalog
description: How to add, run, and iterate on entries in the project's widgetbook-based design catalog (`lib/main_catalog.dart` → `DesignCatalogApp`), AND the token-driven design system the catalog sits on top of. Covers (1) the `@widgetbook.UseCase` annotation + `widgetbook_generator` build_runner workflow, (2) where use case files live (`lib/widgetbook/use_cases/`), (3) how the sidebar hierarchy is derived from the `type:` class location, (4) the fake-cubit pattern for pages that need a cubit/service, (5) the visual verification loop (run on Chrome, switch device/theme axes, edit tokens live), (6) the two-layer `DesignTokens` model (primitives + semantic roles) and how `context.colors` / `context.styles` / `context.spacing` / `context.radius` / `context.iconSize` / `context.motion` cascade through `ThemeProvider`, (7) the legacy `AppSize.*` static-const vs new `context.spacing.*` runtime hybrid, and (8) the Apply-tokens-to-disk pipeline (direct write to `baseline.dart`, desktop-only). Use whenever the user says "add a screen to the catalog", "add to widgetbook", "preview this page", "register a use case", "make a showcase", "use case for X", mentions `@UseCase`, `@widgetbook.UseCase`, "matrix view", "design catalog", "main_catalog.dart", "DesignCatalogApp", "design_catalog package", "widgetbook_generator", `directories.g.dart`, "design tokens", "design system", "context.colors", "context.styles", "context.spacing", "AppSize", "token cascade", "live theme editing", "apply tokens", "token export", asks how to surface a new widget for visual review, or whenever a new page is being created and the team's pattern is to also register it in the catalog.
---

# Widgetbook Catalog

The project hosts a custom matrix-first catalog at `lib/main_catalog.dart`. Run it on Chrome for fast preview, or on a desktop target (macOS/Linux/Windows) to **Apply** token edits directly to `lib/core/theme/tokens/baseline.dart`. Lets you preview any registered widget across every selected device × theme combination.

## MANDATORY: Use case required for every new page

Adding a use case is **not optional** when you create a new page or significant reusable widget — it ships in the same change as the page itself. See [`.claude/rules/widgetbook-use-case-required.md`](../../rules/widgetbook-use-case-required.md) for the full scope (which files trigger the requirement, which state variants must be covered, and the completion checklist). This skill is the HOW; that rule is the WHEN and WHAT.

The short version: when you add a page under `lib/features/<x>/ui/pages/`, you ALSO add `lib/widgetbook/use_cases/<snake_case>_use_case.dart` with one `@widgetbook.UseCase` per distinct visible state (`default`, `loading`, `empty`, `error`, etc.). A `default`-only use case is insufficient for state-bearing pages — designers can't see the spinner, the empty illustration, or the error message, and those drift fastest.

The wiring uses **two layers**:

1. **Annotation + codegen** — `@widgetbook.UseCase` on a top-level builder function. `widgetbook_generator` (build_runner) collects every annotation in the project and produces `lib/widgetbook/widgetbook_app.directories.g.dart` exposing a single `directories` constant.
2. **Custom shell** — `DesignCatalogApp` (from the `design_catalog` package at `tools/design_catalog/`) consumes that `directories` list. We do NOT use `Widgetbook.material()` — our shell renders the sidebar tree, the global top-bar axes (device multi-select dropdown, theme chips, zoom/DPI sliders), the InteractiveViewer matrix canvas, and the token editor panel.

The token editor cascades through `ThemeProvider` to every tile in real time. Hitting **Apply** (desktop targets only) rewrites the primitive blocks in `lib/core/theme/tokens/baseline.dart` directly. On Chrome the button is disabled with a tooltip explaining that — on any failure the catalog falls back to a copy-source dialog so the dev can paste the new blocks manually.

## Critical Rules (Never Break)

0. **Theme tokens are mandatory inside the widget being previewed — never literal colors, magic-number spacing, or inline `TextStyle()`.** *Why:* literals bypass light/dark mode, drift away from the design system, and break the live cascade — a token edit in the side panel won't update the tile. Use `context.colors.*`, `context.styles.*`, `context.spacing.*`, `context.radius.*`, `context.iconSize.*`, `context.motion.*`. The lone carve-out is `AppColors.brand*` static constants on intentionally theme-independent surfaces (auth gradient, iOS-style chips). Prefer semantic over primitive token names: a button reading `context.colors.primary` keeps working if `interactive.primary` is later repointed at a different primitive; `context.tokens.primitives.color.teal500` is fragile.

1. **One use case = one file under `lib/widgetbook/use_cases/<snake_case>_use_case.dart`.** *Why:* the sidebar groups by file imports, but more importantly, this is the project convention — every existing use case follows it. Mixing builders into other folders fragments the catalog.

2. **The annotation goes on a top-level function, not a method.** *Why:* `widgetbook_generator` only picks up top-level functions. `@widgetbook.UseCase(name: '<case>', type: <ClassYouArePreviewing>)` immediately above a `Widget myUseCase(BuildContext context) => ...`.

3. **`type:` is the class whose folder hierarchy you want in the sidebar — not always the widget you return.** *Why:* the generator places the component under the directory tree of where `type:` is declared. For a project page, `type: SplashPage` puts it under `features/auth/ui/pages/SplashPage`. For a synthetic gallery widget defined in the use_case file itself (like `TypographyShowcase`), `type: TypographyShowcase` puts it under `widgetbook/use_cases/TypographyShowcase`. Pick the type that produces the sidebar location you want.

4. **Always run build_runner after adding/renaming a use case.** *Why:* `directories.g.dart` is generated; without rerunning it your new use case will not appear. Command: `dart run build_runner build --delete-conflicting-outputs`.

5. **Use cases own their mocks. NEVER reach for real DI (`getIt<X>()`), real Supabase, real Firebase, or HydratedStorage from inside a use case builder.** *Why:* the catalog binary has no bootstrap pipeline. Hive, Supabase, FCM, and the DI container are not initialized. Anything that touches `getIt`, `Supabase.instance`, `FirebaseMessaging`, or persistent storage will crash the tile (or the whole app). Mock cubits via a hand-built fake; pass fixture data inline; ignore navigation callbacks.

6. **The use case function must return a renderable widget tree on its own.** *Why:* tiles are rendered inside a `MaterialApp` → `Scaffold` envelope provided by `DesignCatalogApp`. The use case adds anything page-specific (the Scaffold for a full page, `BlocProvider.value` for a cubit, etc.). It does NOT need to wrap in its own `MaterialApp` or `MediaQuery` — those come from the shell.

7. **Localization works because the shell installs the project's delegates.** *Why:* `lib/widgetbook/widgetbook_app.dart` passes `AppLocalizations.delegate` + Material/Cupertino/Widgets globals. `context.localization.*` calls inside use cases resolve normally. Don't add a second `Localizations` widget inside a use case.

## The two-layer token model

The catalog edits a token tree defined in the `design_catalog` package. The project's baseline values live at `lib/core/theme/tokens/baseline.dart`.

```
TokenPrimitives
├── color (raw hex values, named by hue + stop — e.g. teal.500 = #2F7874)
├── spacing (numeric scale: 0, 1, 2, 4, 6, 8, …, 64, 96, 100, 999)
├── typography (font family + sizes + weights + line heights + letter-spacings)
├── motion (durations + curves)
└── opacity (alpha values for translucent text)

SemanticColors / SemanticSpacing / SemanticRadius / SemanticIconSize
SemanticTypography / SemanticMotion
└── each role stores the resolved value, regenerated from primitives via
    `buildBaselineTokens(TokenPrimitives)` whenever the catalog edits a primitive.
```

**Primitives** name raw values (`color.teal.500`, `spacing.s16`). They're the catalog's editing surface.

**Semantic roles** name purposes (`color.interactive.primary`, `spacing.cardPadding`, `radius.card`, `text.fieldText`). They're what widget code consumes via `context.*`.

The cascade: edit `primitives.color.teal500` in the side panel → `buildBaselineTokens` rebuilds → `semantic.color.interactivePrimary` is reconstructed against the new primitive → every `context.colors.primary` consumer rebuilds.

### Which extension do I reach for

| Need | Use |
|------|-----|
| A theme-aware color | `context.colors.<role>` (e.g. `context.colors.text`) |
| A typography style | `context.styles.<role>` (e.g. `context.styles.fieldText`) |
| Spacing in *new* code | `context.spacing.<role>` (e.g. `context.spacing.cardPadding`) |
| Radius / icon size | `context.radius.<role>` / `context.iconSize.<role>` |
| Animation duration / curve | `context.motion.<role>` |
| Spacing inside an existing `const` constructor | Keep `AppSize.<name>` (static const) — don't drop `const` |
| A brand-fixed color on auth surfaces | `AppColors.brand*` (static const carve-out) |
| The full `DesignTokens` (rare) | `context.tokens` |

### `AppSize.*` vs `context.spacing.*` (the hybrid)

`AppSize.*` is a **legacy** static-const facade; new code uses `context.spacing.*`. *Why both:* `AppSize.padding` can sit inside `const EdgeInsets.all(...)`, but that also means catalog edits don't live-cascade through it — only the runtime extensions cascade. ~333 existing call sites still use `AppSize.*` (hybrid carve-out); never expand that count. When the live cascade matters (designer iterating in the catalog), use `context.spacing.*`.

### Token discipline rules

1. **No literal colors, magic-number spacing, or inline `TextStyle()` in widget code.** Use the extensions above. Literals bypass light/dark mode AND break the catalog cascade — a token edit won't update the tile.
2. **Prefer semantic over primitive token names.** `context.colors.primary` keeps working if `interactive.primary` is repointed; `context.tokens.primitives.color.teal500` is fragile.
3. **The lone carve-out is `AppColors.brand*`** static constants on surfaces that are intentionally theme-independent (auth gradient, iOS-style success/error/warning chips). Everywhere else, default to `context.colors`.

The exact token names available in *this* project are listed in `tokens.skill-data.md` (sibling of this file), regenerated on every Apply.

## Mental model

```
@widgetbook.UseCase (in lib/widgetbook/use_cases/*.dart)
        │
        ▼  build_runner picks it up
        │
widgetbook_app.directories.g.dart   ◄── do NOT edit by hand
        │
        ▼  imported by widgetbook_app.dart
        │
DesignCatalogApp(directories: directories, ...)
        │
        ├── Sidebar: tree built from directories
        ├── Top bar: global devices/theme/zoom/DPI controls
        ├── Matrix: useCase × selectedDevices × selectedThemes
        └── Token editor: live cascade via ThemeProvider
```

The sidebar hierarchy mirrors the **import path of the `type:` class**, not the import path of the use case file.

## Adding a new use case

**When you add a page, you ALSO add the use case in the same change** — see `.claude/rules/widgetbook-use-case-required.md`. The work below is part of "creating a page", not a follow-up task.

### A. For a feature page (`lib/features/<feature>/ui/pages/<X>Page.dart`)

1. **Create** `lib/widgetbook/use_cases/<snake_case>_use_case.dart`:

   ```dart
   import 'package:core_boilerplate/features/<feature>/ui/pages/<x>_page.dart';
   import 'package:flutter/material.dart';
   import 'package:widgetbook_annotation/widgetbook_annotation.dart'
       as widgetbook;

   @widgetbook.UseCase(name: 'default', type: <X>Page)
   Widget <x>PageUseCase(BuildContext context) => const <X>Page();
   ```

2. **If the page needs a cubit**, provide a fake. Inline subclass of the real cubit (or `Cubit<XState>` when the real one's constructor needs DI):

   ```dart
   @widgetbook.UseCase(name: 'success', type: ItemsPage)
   Widget itemsPageSuccessUseCase(BuildContext context) {
     return BlocProvider<ItemsCubit>.value(
       value: _FakeItemsCubit(const ItemsState(
         status: BlocStatus.success,
         items: _kSampleItems,
       )),
       child: const ItemsPage(),
     );
   }

   class _FakeItemsCubit extends Cubit<ItemsState> implements ItemsCubit {
     _FakeItemsCubit(super.state);
     @override
     dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
   }
   ```

   Add a separate function per state you want to preview (`default`, `empty`, `loading`, `error`, `overflow`). Each gets its own `@widgetbook.UseCase(name: '<state>', type: ItemsPage)`.

3. **Run build_runner:**
   ```bash
   dart run build_runner build --delete-conflicting-outputs
   ```

4. **Hot-restart Chrome.** The new node appears in the sidebar under `features/<feature>/ui/pages/<X>Page`.

### B. For a synthetic gallery widget (typography, colors, buttons showcases)

1. **Define the gallery widget in the same file** so its `type:` lives where you want it shown:

   ```dart
   // lib/widgetbook/use_cases/typography_use_case.dart
   class TypographyShowcase extends StatelessWidget { ... }

   @widgetbook.UseCase(name: 'gallery', type: TypographyShowcase)
   Widget typographyShowcaseUseCase(BuildContext context) =>
       const TypographyShowcase();
   ```

   This puts the entry at `widgetbook/use_cases/TypographyShowcase`.

2. Run build_runner; hot-restart.

## Multiple cases for the same page

Each `@UseCase` annotation = one tile. To show `default` / `empty` / `loading` / `error` for the same page, write four functions in the same file with the same `type:` but different `name:` values. They group under the same component in the sidebar.

## Picking what to render

In the matrix:
- Selecting a **folder** node tiles every use case under it.
- Selecting a **component** node (e.g. `ItemsPage`) tiles all its cases.
- Selecting a **use case** node (e.g. `ItemsPage/success`) tiles just that one across the selected devices/themes.

## Mock pattern — quick reference

| Page needs… | Pattern |
|---|---|
| Pure stateless / no cubit | Return the widget directly (`SplashPage`, `LandingPage`). |
| One feature cubit | Hand-built `_FakeXCubit extends Cubit<XState> implements XCubit` with `noSuchMethod` fallthrough, provided via `BlocProvider.value`. |
| Multiple cubits | One fake per cubit, `MultiBlocProvider` with `.value` providers. |
| AuthCubit / OrganizationCubit (singletons) | Fake same way — they are HydratedCubit but only `state` is read in build. Wrap in `BlocProvider<AuthCubit>.value(value: _fake, child: page)`. |
| A repository or service | Inject a fake at the cubit boundary, not at the widget. If the page reads a service directly (rare), wrap in `RepositoryProvider<X>.value`. |
| Navigation callback / `GoRouter` push | Ignore — pass `() {}`. Catalog tiles are not interactive routing surfaces. |
| Theme | Already provided by the shell + `ThemeProvider`. Don't re-wrap. |

If a page genuinely cannot be mocked without a heroic effort (deep service tree, real database), surface only its non-trivial leaf widgets via synthetic gallery showcases (pattern B) instead of the full page.

## Run + iterate

```bash
# After adding/renaming use cases:
dart run build_runner build --delete-conflicting-outputs

# Launch the catalog on Chrome (preview only — Apply is disabled here):
flutter run -t lib/main_catalog.dart -d chrome --web-port 7654

# Launch the catalog on a desktop target — required to use Apply:
flutter run -t lib/main_catalog.dart -d macos    # or linux / windows
```

The Chrome variant opens at `http://localhost:7654`. Hot-reload works for use case file edits; the generated `directories.g.dart` requires re-running build_runner + hot-restart.

### What the shell gives you

- **Sidebar (left)** — tree built from the codegen. Search filter at top.
- **Top bar** — global axes that apply to every tile:
  - **Devices dropdown** — multi-select with checkmarks (iPhone SE / Pixel 7 / iPad / Desktop 1280).
  - **Theme chips** — Light / Dark multi-select.
  - **Zoom slider** — tile preview scale.
  - **DPI slider** — drives `MediaQuery.devicePixelRatio` AND `textScaler` so the change is visible on web.
  - **Reset / Apply / Palette** — reset in-catalog edits, apply tokens to disk, toggle the editor panel. Apply is disabled on Chrome (filesystem unavailable) and visible-but-disabled tooltip explains why.
- **Matrix canvas** — InteractiveViewer with `Wrap` of tiles for `useCases × devices × themes`. Bottom-right has +/−/fit zoom controls.
- **Token editor (right)** — Colors / Spacing / Type / Motion / Opacity tabs. Edits cascade through `ThemeProvider` to every tile.

## Apply tokens

Hitting **Apply** rewrites the five `const X _defaultXPrimitives = X(...)` blocks in `lib/core/theme/tokens/baseline.dart` *in place*, using the catalog's current edits. The path is configured in `widgetbook_app.dart`'s `ApplyConfig.baselineFilePath`. Apply also rewrites the `.claude/skills/widgetbook-catalog/tokens.skill-data.md` sidecar so future AI suggestions know the exact token names.

Workflow:

1. **Run on a desktop target** — Apply is disabled on Chrome because `dart:io` (and therefore `File.writeAsString`) is unavailable on web. Use macOS / Linux / Windows.
2. **Save any open editor buffers first** — Apply writes directly to `baseline.dart` and your IDE may overwrite the change otherwise. The confirm dialog warns about this.
3. **Click Apply, confirm.** The writer is anchored on the exact header lines (`const ColorPrimitives _defaultColorPrimitives = ColorPrimitives(`) and scans for the matching `);` terminator — `buildBaselineTokens`, `_composeTokens`, imports, and semantic role wiring are NEVER touched. The write is atomic (`.tmp` + rename) and includes a best-effort `dart format` pass.
4. **Hot-restart your running app** to pick up the new baseline. The snackbar includes a `Reset` action to revert the in-catalog edits afterwards.

On web, Apply still emits the source — but instead of writing, the failure dialog opens with a Copy button so you can paste the new blocks into `baseline.dart` manually. Same fallback for any error during the in-place rewrite.

## Common pitfalls

- **"My new use case didn't show up."** Forgot to run `dart run build_runner build --delete-conflicting-outputs`. Or the file is not under `lib/widgetbook/use_cases/`. Or the annotation is on a method instead of a top-level function.
- **"Tile crashes with `Bad state: GetIt: Object not found`."** The page (or one of its widgets) reads `getIt<X>()` directly. Either mock that cubit/service into the tree, OR refactor the widget to take the dependency via constructor.
- **"Tile crashes with `HiveError: Box not opened`."** A `HydratedCubit` is being constructed without HydratedStorage initialized. Provide a fake cubit (`_FakeAuthCubit extends Cubit<AuthState>`) — don't construct the real one.
- **"DPI slider doesn't affect rendering."** It does — but you may be running an old web cache. Hard-refresh Chrome. (The slider drives both `devicePixelRatio` and `textScaler`; if neither moves, the cache is stale.)
- **"Token edits don't show in my widget."** The widget is using `AppSize.*` (static const) or literal colors. Switch to `context.spacing.*` / `context.colors.*` — only the runtime extensions cascade.
- **"Localization throws `Null check operator used on a null value`."** The use case wrapped its own `Localizations` or `MaterialApp`. Remove that — the shell already provides them.
- **"`directories` is undefined when I edit `widgetbook_app.dart`."** That import resolves only after `widgetbook_app.directories.g.dart` exists. Run build_runner.

## Verification checklist

After adding a use case:

- [ ] **If this page is new, did you add the use case in the same change?** (`.claude/rules/widgetbook-use-case-required.md`)
- [ ] File lives at `lib/widgetbook/use_cases/<snake>_use_case.dart`.
- [ ] Annotation is `@widgetbook.UseCase(name: '<case>', type: <Class>)` on a top-level function.
- [ ] Every state the cubit can produce has its own variant (`default`, `loading`, `empty`, `error`, plus any flow-specific states) — a single `default` is insufficient for state-bearing pages.
- [ ] `dart run build_runner build --delete-conflicting-outputs` ran cleanly.
- [ ] `lib/widgetbook/widgetbook_app.directories.g.dart` now imports the new file.
- [ ] Catalog reloaded; new node appears in the sidebar under the expected folder.
- [ ] Tile renders on iPhone SE light + dark without throwing.
- [ ] No `getIt`, `Supabase.instance`, `FirebaseMessaging.*`, or HydratedStorage reach-through in the use case or any widget it builds.
- [ ] Token cascade works: open the palette, change `colors.primary`, the tile updates without restart.

## Where to look

| Concern | File |
|---|---|
| Catalog entry-point | `lib/main_catalog.dart` |
| `@widgetbook.App()` host + `DesignCatalogApp` wiring | `lib/widgetbook/widgetbook_app.dart` |
| Generated tree (do not edit) | `lib/widgetbook/widgetbook_app.directories.g.dart` |
| Existing use cases (reference) | `lib/widgetbook/use_cases/` |
| Catalog shell source | `tools/design_catalog/lib/src/widgetbook/design_catalog_app.dart` |
| Token type definitions | `tools/design_catalog/lib/src/tokens/` |
| Project token baseline | `lib/core/theme/tokens/baseline.dart` |
| Build_runner config | `build.yaml` (root) + `widgetbook_generator` pub dep |

## Cross-references

- → **`/page-creation`** for the page shape (Scaffold envelope, `BlocBuilder`, `Semantics`) before you wrap it in a use case.
- → **`/cubit-creation`** for the cubit shape you'll need to fake.
- → **`/widget-creation`** when extracting a reusable widget that also belongs in the catalog as a gallery showcase.
- → **`/code-generation-workflow`** for the broader build_runner story (Freezed, Retrofit, Injectable, Widgetbook all share the same runner).
