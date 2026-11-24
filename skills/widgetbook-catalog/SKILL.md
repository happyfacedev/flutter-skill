---
name: widgetbook-catalog
description: Internal flutter-skill pattern — invoked via the flutter-skill router, not from this description. (Widgetbook use cases.)
---

# Widgetbook Catalog — use cases

Kit projects ship a Widgetbook component catalog (`lib/main_catalog.dart` entry, use cases under `lib/widgetbook/use_cases/`). It's how designers and QA preview every widget across devices, themes, and states without booting the full app. This skill is the HOW of writing use cases. The WHEN is simple: **every new page or significant reusable widget ships its use case in the same change** — a page without one is invisible to the catalog, and the person who tries to add it later discovers the page reaches into `getIt`/Supabase and crashes the tile. Projects may enforce this with a coverage gate; its absence doesn't waive the rule.

**Discover before writing** — the code is the catalog: read `lib/widgetbook/widgetbook_app.dart` to learn the project's shell (some projects run a custom shell with a live token editor, others stock `Widgetbook.material`) and skim one or two existing files under `lib/widgetbook/use_cases/` for local idiom.

## Critical rules

1. **One use case file per component under `lib/widgetbook/use_cases/`, mirroring the source path and matching the neighboring files' name suffix (`_use_case.dart` / `_use_cases.dart` — projects vary by directory), with `@widgetbook.UseCase(name: '<variant>', type: <Class>)` on a top-level function.** *Why:* the generator only collects top-level functions — an annotated method silently produces nothing; scattered files and mixed-suffix neighbors fragment the sidebar.

2. **`type:` is the class whose declaring file's path you want in the sidebar — not necessarily the widget you return.** `type: ItemsPage` files the tile under `features/items/ui/pages/ItemsPage`; a synthetic showcase class declared in the use case file itself files under `widgetbook/use_cases/`. *Why:* the sidebar tree mirrors the `type:` class's source location; picking the wrong type strands the tile where nobody looks.

3. **One variant per distinct visible state — a lone `default` is insufficient for anything state-bearing.** Pages driven by `BlocStatus` get `default`/`loading`/`empty`/`error` (+ flow-specific states); widgets with `enum` modes get one variant per mode. Same file, same `type:`, different `name:` — they group under one sidebar node. *Why:* the loading spinner, empty illustration, and error copy are exactly the surfaces that drift fastest when nobody can see them.

4. **The catalog binary has NO bootstrap — never let a use case reach real DI, backend, or storage** (`getIt`'s real graph, `Supabase.instance`, Firebase, HydratedStorage — all uninitialized; touching them crashes the tile). Fake at the seam the component actually uses:

   | The component… | Fake mechanic |
   |---|---|
   | Takes the cubit/values via constructor | Pass the fake directly (`cubit: _FakeXCubit(state)`) |
   | Is a page whose `BlocProvider(create: (_) => getIt<XCubit>()..load())` resolves via DI | Idempotent registration at use-case start: `_ensureFake()` that `unregister`s if registered, then `getIt.registerFactory<XCubit>(() => _FakeXCubit(state))` |
   | Consumes an inherited provider (`BlocBuilder` below you) | `BlocProvider<XCubit>.value(value: fake, child: …)` — sanctioned here: the use case owns the fake, and a preview tile is a test-like surface |
   | Reads a repository/service directly (rare) | `RepositoryProvider<X>.value` with a fake — or preview its leaf widgets via a synthetic showcase instead |
   | Navigation callbacks | Pass `() {}` — tiles aren't routing surfaces |

   The fake shape: `class _FakeXCubit extends Cubit<XState> implements XCubit { _FakeXCubit(super.state); }` plus no-op overrides for anything the page calls (`initialize`, `retry`, …). Seed it with the exact state the variant shows.

5. **Don't wrap your own `MaterialApp`, `Localizations`, or theme.** *Why:* the shell already provides them; a second `Localizations` is the classic "Null check operator on null value" tile crash, and a second theme breaks the shell's theming (and live token cascade, where the project has one).

6. **Theme tokens only inside the previewed widget — the `/ui` rules apply unchanged.** *Why:* beyond light/dark correctness, shells with a token editor cascade edits live into every tile; a literal is a dead pixel that ignores the designer's change.

7. **Run `dart run build_runner build --delete-conflicting-outputs` after every add/rename; never hand-edit `widgetbook_app.directories.g.dart`.** *Why:* the sidebar is generated from the annotations — without the build the new tile simply doesn't exist.

## Workflow

1. Discover the shell + local idiom (see above); check the widget/page follows `/ui` (a `getIt` reach-through inside `build` can't be previewed — constructor-inject it first).
2. Write the use case file — [templates/page_use_case.dart](templates/page_use_case.dart) for pages, [templates/widget_use_case.dart](templates/widget_use_case.dart) for reusable widgets and synthetic showcases.
3. NO `context.knobs.*` when the project's design catalog runs without the Widgetbook knob runtime — it renders stories without the Widgetbook knob runtime (a knob call = red error tile). Every state worth seeing is its own fixed `@UseCase` variant (Default / Loading / Disabled / Error).
4. build_runner, then verify: the node appears in the sidebar, and the tile renders on the smallest device × both themes without throwing.

## Bulk backfill (coverage gate)

When the project has a coverage checker (kit projects: `dart run tools/check_widgetbook_coverage.dart --json` → `{"gaps": [{"file", "class"}]}`): for each gap, read the widget, pick the fake seam from the Rule 4 table, and write the use case. A widget that genuinely can't be previewed (plugin-bound: camera, file picker) goes on the checker's ignore list with a one-line reason — never a fake `default` that renders nothing. Finish with build_runner + `flutter analyze lib/widgetbook/` + the checker green.

## Optional adjuncts

- **Golden tests**: use cases double as golden-test sources (`widgetbook_golden_test`) — offer when the team wants visual regression on the catalog; don't impose it.
- The catalog pays for itself on teams enforcing design-system parity; for a throwaway prototype, skip the backfill sweep, not the per-change rule.

## Checklist

- [ ] File at `lib/widgetbook/use_cases/<snake_case>_use_case.dart`; annotations on top-level functions with explicit `name:` + `type:`
- [ ] Every distinct visible state / enum mode has its own variant function
- [ ] No real DI, `Supabase.instance`, Firebase, or HydratedStorage anywhere in the tile's tree — fakes per the Rule 4 seam table, seeded with the variant's exact state
- [ ] No own `MaterialApp` / `Localizations` / theme wrapper
- [ ] Previewed widget reads tokens via `context.*` only (`/ui`)
- [ ] build_runner ran; `widgetbook_app.directories.g.dart` references the new file
- [ ] Tile renders on the smallest device, light + dark, without throwing
- [ ] (Coverage-gate projects) `check_widgetbook_coverage.dart` passes; ignore-list entries carry a reason
