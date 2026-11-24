---
name: page-creation
description: Creates Flutter pages (screens) in `features/<x>/ui/pages/` — the canonical `StatelessWidget` page + `BlocProvider(create:)` + inner private `StatelessWidget` view + `BlocBuilder(buildWhen:)` shape, with `Semantics(identifier:)` placement, theme tokens (`context.colors` / `context.styles` / `AppSize`), `Scaffold` + `SafeArea` envelope, and switch-on-`BlocStatus` for loading/success/empty/error rendering. Covers list pages (pull-to-refresh, tap-to-detail, empty + error variants), detail pages (`MultiBlocProvider` + `MultiBlocListener` for side effects like snackbars and modals), and the multi-cubit composition pattern. Use when adding any file under `ui/pages/`, restructuring a page, deciding where to place `BlocProvider` vs `BlocBuilder` vs `Semantics`, picking which subset of state to wrap a `BlocBuilder` around, or when the user mentions "page", "screen", "scaffold", "Scaffold", "route page", "view", "BlocBuilder buildWhen", "MultiBlocListener", "page structure", or "where do I put X in the page". Cubit shape itself → /cubit-creation. Forms → /form-creation (or `formz` inputs). Route entry → /navigation-gorouter. Extracting feature widgets → /widget-creation.
argument-hint: "[feature-name]"
---

# Page Creation

A page is the top-level widget for a route — what `GoRouter` renders. Its job is to **provide the cubits its UI needs**, **arrange the Scaffold envelope**, and **delegate every meaningful slice of state to a `BlocBuilder` that only rebuilds when *its* slice changes.** Pages do not own business logic; that lives in the cubit. Pages do not own data shape; that lives in the model. Pages own *structure + visual mapping of state*.

This skill is about how to build that structure correctly. For the cubit + state shape itself, see `/cubit-creation`. For extracting reusable widgets out of a page, see `/widget-creation`. For wiring the page into the router, see `/navigation-gorouter`.

## Critical Rules (Never Break)

1. **The outer page widget is a `StatelessWidget` and its only job is to provide cubits.** *Why:* `BlocProvider(create:)` owns the cubit lifecycle. If you make the page a `StatefulWidget` to call something in `initState`, you've moved logic out of the cubit and into the widget tree — and now `dispose` has to mirror `initState`, the cubit is created somewhere `BlocProvider` can't see, and tests have to mount a widget to verify cubit behavior. The carve-out: when controllers (`TextEditingController`, `ScrollController`, `AnimationController`) are genuinely needed, push them into the *smallest* inner widget that owns them — never the page root.

2. **An inner private `_FeatureView` `StatelessWidget` consumes the cubit.** *Why:* the page widget that calls `BlocProvider` cannot read the cubit it just created via `context.read` in the same `build` — the provider isn't in scope yet. The standard split is `FeaturePage` (provides) → `_FeatureView` (consumes). Mark the inner view `private` with a leading underscore so it can't leak.

3. **Every `BlocBuilder` declares `buildWhen`.** *Why:* without `buildWhen`, the widget rebuilds on every state change, even ones it doesn't render. A page with 5 unfiltered `BlocBuilder`s rebuilds every section on every emit. Compare the *specific slices* the builder consumes: `buildWhen: (p, c) => p.status != c.status || p.items != c.items`. Builders only checking `state.status` should compare only `status`.

4. **`context.read<Cubit>()` only inside callbacks. `BlocBuilder` (or `context.watch`) inside `build`.** *Why:* `context.read` doesn't subscribe, so a `build` that calls `context.read` to draw something will silently fail to rebuild when that something changes. Callbacks (`onPressed`, `onTap`, listener callbacks) run *after* `build`, so `context.read` there is the right tool — it grabs the current cubit and dispatches an action.

5. **Side effects (snackbars, dialogs, navigation in response to state) go in `BlocListener` / `MultiBlocListener` with `listenWhen`.** *Why:* `BlocBuilder` is for rebuilding visual content. `BlocListener` is for firing imperative actions exactly once per matching transition. Mixing them — e.g. showing a snackbar from a `BlocBuilder` `builder` — fires the snackbar on every unrelated rebuild and triggers "setState during build" errors. The `listenWhen` predicate is required for the same reason `buildWhen` is.

6. **Every user-interactable element is wrapped in `Semantics(identifier:)` with a stable, kebab-case identifier.** *Why:* Maestro E2E flows target nodes by identifier. An unwrapped button is invisible to the test suite. The identifier convention is `<feature>-<element>[-<qualifier>]` — see `reference.md` for examples. Identifiers do not get localized. Decorative elements (icons, dividers, static text) are skipped.

7. **Theme tokens are mandatory: `context.colors`, `context.styles`, `AppSize`.** *Why:* literal `Color(0x...)`, inline `TextStyle(fontSize: ...)`, and magic numbers (`EdgeInsets.all(16)`) bypass light/dark mode, drift away from the design system, and are impossible to update centrally. The carve-out: `AppColors.brand*` static constants are allowed where the surface is intentionally theme-independent (e.g., the auth gradient renders identically in light + dark). When unsure, default to `context.colors`. See `reference.md` for the full token catalog.

## Decision: which page shape

| Shape | When | Template |
|---|---|---|
| **List page** | Showing a collection (a list of items) — has pull-to-refresh, empty/error variants, tap-to-detail | [`templates/list_page.dart`](templates/list_page.dart) |
| **Detail page** | Single entity with sub-sections + action bar + side effects (snackbar after action) — usually multi-cubit | [`templates/detail_page.dart`](templates/detail_page.dart) |
| **Form page** | Input fields backed by `formz` inputs and a submit action | Combine the detail-page shape with `/form-creation` |

Both templates use the same primitives — they differ in composition (single cubit + list vs multiple cubits + listener for side effects). Pick the closer one and adapt.

## Anatomy of a page

The patterns below are encoded in the templates — this section explains *why* each piece is shaped the way it is, so you can adapt when reality doesn't match the template exactly.

### Provider layer (outer `StatelessWidget`)

```dart
class FeaturePage extends StatelessWidget {
  const FeaturePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<FeatureCubit>()..loadData(),
      child: const _FeatureView(),
    );
  }
}
```

- **`..loadData()` (cascade)** kicks off the initial load on construction. The cubit emits `BlocStatus.loading`, and the inner view's `BlocBuilder` picks it up on the first frame.
- **`MultiBlocProvider`** when the page needs more than one cubit. Order doesn't matter for unrelated cubits; for cubits that read each other's state via a parent `BlocListener` (see Detail template), the producer must be above the listener.
- **Never use `BlocProvider.value` at the page level** — that aliases an externally-owned instance. The only legitimate places for `.value` are the composition root and tests.

### View layer (inner private `StatelessWidget`)

```dart
class _FeatureView extends StatelessWidget {
  const _FeatureView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Column(/* ... composed of section widgets ... */),
      ),
    );
  }
}
```

- **`Scaffold` + `SafeArea`** is the canonical envelope. Don't wrap `Scaffold` in `Padding` — let inner sections own their own padding.
- **Sections are extracted into private `_FooSection` widgets** within the same file (or moved to `ui/widgets/` if reused). Avoid `Widget _buildHeader()` methods — they're invisible to the widget tree, can't be `const`, and aren't independently rebuildable. See `/widget-creation`.

### BlocBuilder placement: as deep as possible

A common mistake is wrapping the entire page in a single `BlocBuilder` and switching the whole UI on `state.status`. That rebuilds the static header and footer every time the list reloads. Instead, **push the `BlocBuilder` down to the smallest widget that actually depends on the state**:

```dart
// ✗ Top-level builder — rebuilds the header on every list change
BlocBuilder<FeatureCubit, FeatureState>(
  builder: (context, state) => Column(
    children: [
      const _Header(),                     // static, but rebuilds anyway
      Expanded(child: _List(items: state.items)),
    ],
  ),
)

// ✓ Builder wrapping only the dynamic part
Column(
  children: [
    const _Header(),                       // truly const, never rebuilds
    Expanded(child: _ListSection()),       // owns its own BlocBuilder
  ],
)
```

### Switch on `BlocStatus`

For a list page or any cubit using `BlocStatus`, render with a switch expression:

```dart
return switch (state.status) {
  BlocStatus.initial || BlocStatus.loading when state.items.isEmpty =>
    const Center(child: CircularProgressIndicator()),
  BlocStatus.failure => _ErrorContent(onRetry: cubit.refresh),
  _ => _SuccessList(items: state.items),
};
```

The guard `when state.items.isEmpty` is the standard "show a spinner on first load, but keep the list visible when refreshing" pattern. Subsequent loads (with `items` already populated) fall through to `_SuccessList`, which shows the list with a `RefreshIndicator`.

### Side effects: `BlocListener` with `listenWhen`

When a state transition should trigger a snackbar, dialog, or navigation:

```dart
MultiBlocListener(
  listeners: [
    BlocListener<FeatureCubit, FeatureState>(
      listenWhen: (p, c) => p.actionStatus != c.actionStatus,
      listener: (context, state) {
        if (state.actionStatus == BlocStatus.success) {
          ScaffoldMessenger.of(context).showSnackBar(/* ... */);
        }
      },
    ),
  ],
  child: /* ... */,
)
```

- `listenWhen` is required — same reasoning as `buildWhen`.
- The listener does NOT rebuild; it only fires the callback. Keep visual rendering inside `BlocBuilder`.
- For multi-cubit detail pages, group all listeners under a single `MultiBlocListener`.

### Semantics placement

Wrap the **actual interactable**, not its parent container:

```dart
// ✓ Maestro taps the InkWell; the identifier rides exactly the hit area
Semantics(
  identifier: 'items-card-$index',
  child: InkWell(onTap: onTap, child: /* card content */),
)

// ✗ Identifier on the outer Padding — Maestro can find it but
// `tap` may not propagate to the InkWell, depending on layout
Semantics(
  identifier: 'items-card-$index',
  child: Padding(
    padding: ...,
    child: InkWell(onTap: onTap, child: /* card content */),
  ),
)
```

For widgets that expose a `semanticsIdentifier` parameter (e.g., `MainButton`), pass it directly rather than wrapping externally.

## What this skill does NOT cover

This skill is the canonical home for **page structure and visual state mapping**. It defers everything else:

- **The cubit + state shape itself** → `/cubit-creation`
- **The token policy** (must-use-`context.colors`, etc.) → `rules/ui-standards.md`
- **The token catalog** (values of `AppSize.*`, `context.styles.*`, `context.colors.*`) → [`reference.md`](reference.md)
- **Extracting a widget out of the page** → `/widget-creation`
- **Adding the route entry** → `/navigation-gorouter`
- **Form inputs with `formz`** → `/form-creation`
- **Localization keys** (`context.localization.foo`) → `/localization-arb`
- **The `Failure` getTitle/getSubtitle contract** for error display → `/failure-modeling`

## Templates

- [`templates/list_page.dart`](templates/list_page.dart) — list + pull-to-refresh + tap-to-detail + status switch + empty/error states
- [`templates/detail_page.dart`](templates/detail_page.dart) — multi-cubit + `MultiBlocListener` for snackbars + action bar + content sections

Replace `Feature` with the feature name (`FeaturePage` → `ItemsPage`, `_FeatureView` → `_ItemsView`, etc.).

## Reference

See [reference.md](reference.md) for:
- `AppSize` constants — full catalog (prefer `s*` constants for new code; legacy `padding`/`smallPadding`/etc. aliases are kept for back-compat)
- `context.styles` text styles — all 12+ styles with their fontSize/weight/use case
- `context.colors` theme-aware colors — full catalog
- `AppColors.brand*` static colors — the carve-out, when it's OK to use them directly
- `BuildContext` extensions — `context.colors`, `context.styles`, `context.isDark`, `num.vSpace` / `num.hSpace`
- Semantics identifier naming convention + examples

## Checklist

- [ ] Outer page widget is `StatelessWidget`, returns `BlocProvider(create: (_) => getIt<...>()..loadAction())` (or `MultiBlocProvider` for multi-cubit pages)
- [ ] Inner view is a private `_FeatureView extends StatelessWidget`
- [ ] `Scaffold` + `SafeArea` envelope; `backgroundColor: context.colors.background` (or static brand if intentionally theme-independent)
- [ ] Each `BlocBuilder` has a `buildWhen` predicate that compares *only* the slices it consumes
- [ ] Each `BlocListener` has a `listenWhen` predicate; side effects (snackbars, dialogs, nav) only happen here
- [ ] `context.read<Cubit>()` appears only inside callbacks, never inside `build`
- [ ] Status branching uses a switch expression on `BlocStatus` with the "first-load spinner / keep-list-on-refresh" guard pattern where applicable
- [ ] Every interactable wraps the *actual* interactable in `Semantics(identifier:)`; identifier is kebab-case `<feature>-<element>[-<qualifier>]`
- [ ] No literal colors, inline `TextStyle()`, or magic numbers — only `context.colors` / `context.styles` / `AppSize` (or `AppColors.brand*` where the carve-out applies)
- [ ] Error display uses `failure.getTitle(context)` / `getSubtitle(context)` — see `/failure-modeling`
- [ ] No `Widget _buildX()` methods — sections are extracted into `_FooSection` private `StatelessWidget`s in the same file
- [ ] If a route entry is needed, follow `/navigation-gorouter` to wire it
