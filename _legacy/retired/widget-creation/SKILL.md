---
name: widget-creation
description: Creates Flutter widgets — feature-private `_FooSection` widgets inside a page file, reusable feature widgets in `lib/features/<x>/ui/widgets/`, and shared reusable widgets in `lib/core/widgets/` or `lib/core/design/`. Covers the reuse-first principle (always search core/widgets and core/design first), the no-`Widget _buildX()` rule (extract to a `StatelessWidget` class, not a builder method), the feature-private vs core promotion decision, the `Ds*` design-system family vs the generic `core/widgets/` family, `semanticsIdentifier` hoisting through wrapper widgets, `const` constructor enforcement, and when extracting a widget out of a page file is justified vs leaving it inline. Use when extracting a section of a page into a separate widget, creating a new reusable button / card / chip / row, promoting a feature widget to core, deciding whether a widget belongs in `core/widgets/` vs `core/design/`, or when the user mentions "widget", "extract widget", "StatelessWidget", "_buildX", "reusable component", "MainButton", "BaseTextField", "Ds prefix", "design system widget", or "feature widget". Page-level structure (Scaffold + BlocProvider + BlocBuilder) → /page-creation. Form inputs (`FormzInput`) → /form-creation. Cubit shape → /cubit-creation.
argument-hint: "[widget-name]"
---

# Widget Creation

A widget in this project is one of three things:

1. **Feature-private section** — a small `_FooSection` `StatelessWidget` inside a page file, used once by that page to organize its tree.
2. **Feature widget** — a non-trivial widget under `lib/features/<x>/ui/widgets/`, used by multiple pages of the same feature.
3. **Shared widget** — `lib/core/widgets/` (generic, `context.colors`-driven) or `lib/core/design/` (the `Ds*` family for static-brand auth/onboarding surfaces).

Pick the smallest scope that fits. **Promote up only when reuse is real**, not anticipated. A `_HeaderRow` that exists in one page should stay private to that page — moving it to `ui/widgets/` "in case another page needs it" creates premature abstraction.

## Critical Rules (Never Break)

1. **NEVER `Widget _buildX()` builder methods inside a class.** Always extract into a separate `StatelessWidget` class. *Why:* builder methods can't be `const`, don't show up in the widget tree (invisible to inspector and Maestro), can't be independently rebuilt, and can't be moved without rewriting the call site. A `_HeaderSection extends StatelessWidget` has none of these drawbacks and the same syntactic weight.

2. **Search before creating.** Before adding a new button, card, chip, row, or input, search `lib/core/widgets/`, `lib/core/design/`, and the current feature's `ui/widgets/`. *Why:* the codebase already has `MainButton`, `BaseFormTextField`, `LoadingWidget`, `ErrorMessageWidget`, plus the full `Ds*` family (`DsPrimaryButton`, `DsScreen`, `DsListCard`, `DsCheckboxRow`, `DsChoiceChip`, …). Recreating one of these in a feature folder is the most common kind of drift caught in review.

3. **All public widget constructors are `const`** unless they receive a non-const argument (in which case the *call site* uses `const` where possible). *Why:* `const` widgets are reconstructed once and reused on every rebuild — losing it is a real perf regression in lists.

4. **Hoist `semanticsIdentifier` as a constructor parameter** when the widget wraps an interactable. *Why:* the caller knows which feature-specific identifier to assign (`items-card-$index`) but doesn't want to re-wrap your widget in `Semantics(identifier: ...)`. `MainButton` and `DsPrimaryButton` both take `semanticsIdentifier` as a parameter and apply it internally — match that pattern when building anything tappable.

5. **Theme tokens come from `context.*`.** Inside a widget's `build`, use `context.colors`, `context.styles`, and `AppSize.*`. The carve-out for `AppColors.brand*` static colors applies only on intentionally theme-independent surfaces (auth gradient, status chips with iOS-style fixed colors). The `Ds*` family uses static colors deliberately — see decision below.

## Decision: where does this widget live?

```
Is the widget used in exactly one place, with no clear reuse on the horizon?
├── YES → private _FooSection StatelessWidget in the same page file
└── NO ↓

Is the widget specific to one feature's domain (e.g., an "item card" or "organization row")?
├── YES → lib/features/<feature>/ui/widgets/foo_widget.dart
└── NO ↓

Does it render on the auth / intro / onboarding surfaces (dark gradient, theme-independent)?
├── YES → lib/core/design/ds_<name>.dart (Ds* prefix, uses AppColors.brand* statics)
└── NO  → lib/core/widgets/<name>.dart (uses context.colors theme-aware tokens)
```

### Why two `core/` widget families?

| Family | Path | Color source | Used by |
|---|---|---|---|
| **`core/widgets/`** (generic) | `lib/core/widgets/` | `context.colors` / `context.styles` (theme-aware) | Authenticated post-startup surfaces — home, items, organizations, settings, etc. |
| **`core/design/`** (the `Ds*` family) | `lib/core/design/` | `AppColors.brand*` statics (theme-independent) | Splash, intro carousel, landing, login, register, forgot-password, email verification, onboarding |

The `Ds*` widgets render the same in light and dark mode because the design renders a dark gradient on those surfaces regardless of user theme. They are NOT a replacement for the generic family on themed surfaces — using a `DsPrimaryButton` on the home page would lock the button into the dark-surface brand palette and miss dark-mode adaption.

When in doubt about which family the new widget belongs to:
- "What surface does it render on?" — auth/onboarding → `Ds*`; everything else → `core/widgets/`
- "Does its color come from `context.colors` or `AppColors.brand*`?" — the former → `core/widgets/`

## Extracting from a page file — the `_FooSection` pattern

Pages tend to get long. The right time to extract a section is when:
- It has more than ~30 lines of build code
- It's a distinct visual unit (a header row, a stats card, an empty-state, an action bar)
- It has its own `BlocBuilder` consuming a different slice of state than the rest of the page (see `/page-creation` — pushing `BlocBuilder` down to the smallest widget is a perf concern)

```dart
// Inside the page file, after the public page + private _FooView:

class _FooHeader extends StatelessWidget {
  const _FooHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSize.s20, AppSize.s16, AppSize.s20, 0,
      ),
      child: Text(
        context.localization.featureTitle,
        style: context.styles.pageTitle,
      ),
    );
  }
}
```

Leading underscore so the section can't leak across files. `const` constructor so the section is reconstructed once.

### When to promote out of the page file

Promote `_FooSection` → `ui/widgets/FooSection` only when:
- A second page (in the same feature) starts needing it, OR
- It grows to a non-trivial size with internal state branching (`BlocBuilder`, conditional rendering) that's distracting in the page file, OR
- It's reused enough that the call site benefits from a public name

"In case we need it later" is not on this list.

## Building a reusable widget — the canonical shape

```dart
import 'package:flutter/material.dart';
import 'package:core_boilerplate/core/theme/theme.dart';

class FooCard extends StatelessWidget {
  const FooCard({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.semanticsIdentifier,
    super.key,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? semanticsIdentifier;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: semanticsIdentifier,
      button: true,
      child: Material(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppSize.radius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSize.radius),
          child: Padding(
            padding: const EdgeInsets.all(AppSize.s16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.styles.subtitle),
                const SizedBox(height: AppSize.s4),
                Text(subtitle, style: context.styles.caption),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

Notes baked into the template:
- `const` constructor with `super.key` last
- `required` for non-optional parameters; nullable types for optional ones (`this.semanticsIdentifier`)
- `Semantics(identifier: ...)` at the outer level, applied unconditionally — a `null` identifier means "not under test"; that's fine and Maestro won't try to target it
- `Material` + `InkWell` for tappable cards so ripple feedback works (a bare `GestureDetector` doesn't ripple)
- Token-driven colors / styles / padding throughout

## When `StatefulWidget` is justified inside a widget

Default to `StatelessWidget`. Reach for `StatefulWidget` only when:
- You need a `TextEditingController`, `ScrollController`, `AnimationController`, `FocusNode`, or other controller that requires `dispose`
- You need to react to widget-lifecycle events (`didChangeAppLifecycleState`, `addObserver`)
- You need a private piece of UI-only state that doesn't belong in a cubit (animation tween value, "is the password obscured", "is the menu expanded")

Even then, isolate the `StatefulWidget` to the smallest possible widget. The outer widget stays `StatelessWidget`; the controller-owning inner `_FooBodyState` is what's stateful. See `MainButton` in `lib/core/widgets/main_button.dart` for the pattern — `MainButton` is `StatelessWidget` and delegates to `_MainButtonBody`.

## Form input widgets are different

If you're building a widget that wraps a `TextField` for a specific input semantic (email, password, name, phone), don't build it as a regular widget — that's the `FormzInput` pattern. See `/form-creation` for `FormzInput<T, E>` classes that live in `lib/core/widgets/form_inputs/`. The actual visual widget (`BaseFormTextField`) already exists and accepts your validator; you don't typically write a new text-field widget per input.

## What this skill does NOT cover

- **Page structure** (Scaffold, BlocProvider, BlocBuilder placement) → `/page-creation`
- **Form input classes** (`FormzInput<T, E>`, validators, dirty/pure state) → `/form-creation`
- **Cubit shape** (when a widget needs its own cubit) → `/cubit-creation`
- **Theme token values** (full catalog of `AppSize`, `context.styles`, `context.colors`) → `/page-creation` reference
- **Semantics policy** (which widgets MUST be wrapped) → `rules/ui-standards.md` policy + `/page-creation` for the where/how

## Templates

- [`templates/feature_widget.dart`](templates/feature_widget.dart) — a feature-scoped widget under `features/<x>/ui/widgets/` with `semanticsIdentifier` hoisting
- [`templates/core_widget.dart`](templates/core_widget.dart) — a generic reusable widget for `core/widgets/`, including the `StatelessWidget` outer + `_FooBody` inner split when an inner stateful piece is needed

## Reference

See [reference.md](reference.md) for:
- The current `core/widgets/` catalog (what already exists — search this FIRST)
- The current `core/design/` `Ds*` catalog
- The feature-private vs feature-shared vs core decision tree as a quick lookup
- When `StatefulWidget` is justified inside a widget — the four legitimate cases

## Checklist

- [ ] Searched `core/widgets/`, `core/design/`, and the current feature's `ui/widgets/` for an existing equivalent
- [ ] If extracting from a page: section is non-trivial (>30 lines or a distinct visual unit or owns its own `BlocBuilder`) — not premature
- [ ] Widget class is `StatelessWidget` unless a controller is genuinely needed; if `StatefulWidget`, isolated to the smallest possible inner widget
- [ ] `const` constructor with `required` named params and `super.key` last
- [ ] `semanticsIdentifier` hoisted as a constructor parameter if the widget wraps an interactable
- [ ] Colors / styles / spacing via `context.colors` / `context.styles` / `AppSize` — or `AppColors.brand*` only if this is a `Ds*` widget on a theme-independent surface
- [ ] No `Widget _buildX()` builder methods anywhere in the file
- [ ] Right location chosen: private to page file / feature widget folder / `core/widgets/` (themed) / `core/design/` (`Ds*`-prefixed, theme-independent)
- [ ] If new in `core/`, justified by reuse-in-the-real ≥ 2 callers — not anticipated
