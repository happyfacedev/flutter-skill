---
name: ui
description: Internal flutter-skill pattern — invoked via the flutter-skill router, not from this description. (Pages, widgets, sections, design-system usage.)
---

# UI — Pages, Widgets & the Design Style

One pattern for all visual work: building the page for a route, extracting sections, creating reusable widgets, deciding where each one lives — and doing all of it inside the project's design style.

Cubit/state shape → `/cubit-creation`. Form inputs → `/form-creation`. Route wiring → `/navigation-gorouter`. Failure display contract (`getTitle`/`getSubtitle`) → `/failure-modeling`.

## The design style is law

Every project carries a codified design style: semantic tokens exposed as `BuildContext` extensions and a reusable widget inventory. That style was decided deliberately with the user in a dedicated `/design-style` session and codified via `/design-codify` — UI work **applies** it; it never extends or bends it ad-hoc.

Before writing any UI, discover what exists — the code is the catalog, there is no separate document to trust:

1. **Widget inventory**: list `lib/core/widgets/` (the design-system tier — every shared component, plain names like `PrimaryButton`, `PillInput`) plus the current feature's `ui/widgets/`. Reuse before creating — recreating an existing button/field/card is the most common drift caught in review.
2. **Token groups**: skim `lib/core/theme/extensions.dart` for the groups this project exposes (`context.colors / styles / spacing / radius / iconSize / motion`), then read the group you need. Pick roles **by intent, not by pixel value**: `spacing.paddingCard` because it's a card interior, `radius.button` because it's a CTA — not "whichever token equals 16".

When the style has no token or component for what you need, that's either a discovery miss (look again) or a real gap. **Check `design/DESIGN_SPEC.md` first** — the missing piece may be a recorded `N/A` with a reason and a reopen trigger, which is a *decision*, not a gap; cite that entry when you surface it. Also honor the spec's **Invariants** section: usage rules that tokens can't express (a component only on certain surfaces, a spacing rule, a never-do) still bind `/ui`. A genuine gap is a **design decision**: surface it to the user and suggest a `/design-style` session (user-run — never invoke it yourself) — never patch it with a literal value, a one-off `TextStyle`, or a private variant of an existing widget.

## Page anatomy

```dart
class FeaturePage extends StatelessWidget {          // provides
  const FeaturePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<FeatureCubit>()..loadItems(),
      child: const _FeatureView(),
    );
  }
}

class _FeatureView extends StatelessWidget {         // consumes
  const _FeatureView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(child: /* section widgets */),
    );
  }
}
```

- The cascade `..loadItems()` kicks off the initial load; the view's `BlocBuilder` catches the first `loading` emit. `MultiBlocProvider` when the page needs several cubits.
- `Scaffold` + `SafeArea` is the envelope. Don't wrap the `Scaffold` in `Padding` — sections own their own padding.
- Sections are private `_FooSection` `StatelessWidget`s in the same file (never `Widget _buildX()` methods — core rule).

## Critical rules

1. **The page widget is a `StatelessWidget` whose only job is to provide cubits; a private `_FeatureView` consumes them.** *Why:* `BlocProvider(create:)` owns the cubit lifecycle, and the widget that creates a provider cannot `context.read` it in the same `build` — the provider isn't in scope yet. Making the page a `StatefulWidget` to call `initState` moves logic out of the cubit and forces tests to mount widgets to reach it.

2. **Every `BlocBuilder` declares `buildWhen` comparing only the slices it renders — and sits on the smallest widget that depends on that state.** *Why:* an unfiltered builder rebuilds on every emit, including ones it doesn't render; a page-level builder rebuilds static headers whenever the list changes. `buildWhen: (p, c) => p.status != c.status || p.items != c.items` for a builder that renders status + items — nothing more.

3. **`context.read<Cubit>()` only inside callbacks; rendering subscribes via `BlocBuilder`.** *Why:* `read` doesn't subscribe — a `build` that draws from `context.read` silently never updates. Callbacks run after `build`, so `read` there is exactly right: grab the cubit, dispatch the action.

4. **Side effects — snackbars, dialogs, navigation-on-state — fire from `BlocListener` with `listenWhen`, never from a builder.** *Why:* builders run on every rebuild; a snackbar inside one fires repeatedly and triggers "setState during build". A listener fires exactly once per matching transition. Group several under `MultiBlocListener`.

5. **Render status with a switch on `BlocStatus`, guarding the spinner with `when state.items.isEmpty`.** *Why:* the guard distinguishes first load (spinner) from refresh (keep showing the list while `RefreshIndicator` spins) — without it every refresh blanks the screen.

6. **Placement ladder — the smallest scope that fits, promoted only on real reuse.** Private `_FooSection` in the page file → `lib/features/<x>/ui/widgets/` when a *second page in the same feature* actually needs it → `lib/core/` only with two or more real feature consumers. *Why:* "in case another page needs it" is premature abstraction, and promotion to `core/` changes app-wide surface — it's the user's call, not an implementation detail. Working headless or unsure: keep it feature-local and note the promotion candidate.

7. **Reusable interactables hoist `semanticsIdentifier` as a constructor parameter and apply it internally; `Semantics` wraps the actual interactable, not a parent container.** *Why:* the caller knows the feature-specific identifier (`items-card-$index`); wrapping a `Padding` instead of the `InkWell` can leave Maestro tapping a region that doesn't hit the gesture target. Use `Material` + `InkWell` for tappable surfaces — a bare `GestureDetector` gives no ripple feedback.

8. **`StatefulWidget` only for widget-local mechanics — controllers needing `dispose`, lifecycle observers, pure UI-only state, debounce timers — isolated to the smallest inner widget.** *Why:* anything observable from outside the widget or with business meaning belongs in the cubit. The canonical split keeps the outer widget stateless (public API + `Semantics`) and delegates to a private stateful body — see [templates/core_widget.dart](templates/core_widget.dart).

## One widget family

All shared components live in `lib/core/widgets/` with plain names (`PrimaryButton`, `SecondaryButton`, `GhostButton`, `PillInput`, `ListCard`, `BottomSheetModal`, …) and read every design value through the `context.*` theme extensions — swap the theme and the whole tier rethemes. Never restyle a tier component at the call site; if it can't express the design, that's a component gap to surface, not a reason for a raw Material widget. Surfaces that intentionally render identically in both themes (the auth gradient shell) keep their widgets feature-private (e.g. `lib/features/auth/ui/widgets/auth_shell/`) under the sanctioned static-color carve-out.

## Templates

- [templates/list_page.dart](templates/list_page.dart) — list + pull-to-refresh + status switch + empty/error states + tap-to-detail
- [templates/detail_page.dart](templates/detail_page.dart) — multi-cubit + `MultiBlocListener` side effects + action bar
- [templates/feature_widget.dart](templates/feature_widget.dart) — feature-scoped widget with `semanticsIdentifier` hoisting
- [templates/core_widget.dart](templates/core_widget.dart) — core widget with the stateless-outer / stateful-body split

Token roles in the templates (`spacing.pagePadding`, `radius.card`, `iconSize.chevron`, …) follow the kit's standard token set — confirm the names against the project's own theme extensions before using them.

## Reference

See [reference.md](reference.md) for:
- Semantics identifier naming convention + examples (list indices, modal grouping, stability contract)
- The four legitimate `StatefulWidget` cases in detail
- Placement / promotion quick lookup
- Where to discover tokens and widgets in an unfamiliar project

## Checklist

- [ ] Listed `lib/core/widgets/` (+ feature `ui/widgets/`) before creating anything — reused where possible
- [ ] Tokens chosen by semantic intent from the project's own extension groups — no literals, no pixel-matching, no new ad-hoc styles
- [ ] Style gaps surfaced to the user / design-style process — not improvised
- [ ] Changed a codified token/widget value? The matching `DESIGN_SPEC.md` entry is superseded (and `tokens.json` updated) in the same change — never silently
- [ ] Outer page `StatelessWidget` + `BlocProvider(create: (_) => getIt<...>()..load())`; private `_FeatureView` consumes
- [ ] Every `BlocBuilder` has `buildWhen` narrowed to its slices, placed on the smallest dependent widget
- [ ] `context.read` only in callbacks; side effects only in `BlocListener` with `listenWhen`
- [ ] Status switch uses the first-load spinner guard; error display uses `failure.getTitle(context)` / `getSubtitle(context)`
- [ ] Widgets placed at the smallest fitting scope; `core/` promotion only with real ≥2-feature reuse and user approval
- [ ] Interactables: `Semantics(identifier:)` on the actual interactable; reusable widgets hoist `semanticsIdentifier`; `Material` + `InkWell` for taps
- [ ] `StatefulWidget` only for the four widget-local cases, isolated to the smallest inner widget
- [ ] No raw Material interactable where a `core/widgets/` component exists — `tools/check_ui_conventions.dart` (when present) enforces this
