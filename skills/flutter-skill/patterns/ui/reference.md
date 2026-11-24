# UI — Reference

Conventions that don't drift. Inventories (which widgets exist, which token roles exist, their values) are deliberately NOT mirrored here — the code is the catalog. The retired hand-mirrored catalogs were already wrong within weeks (widgets renamed, token systems replaced); read the source instead.

## Discovering the design system in a project

| What | Where |
|---|---|
| Token groups the project exposes | `lib/core/theme/extensions.dart` — the `BuildContext` getters (`colors`, `styles`, `spacing`, `radius`, `iconSize`, `motion`, …) |
| Role names + values per group | The class each getter returns — follow the import (may live in a local package such as `tools/design_catalog/`) |
| Widget inventory | `/project-facts` when the project provides it; otherwise `ls lib/core/widgets/` (subfolders like `form_inputs/` belong to `/form-creation`) |
| Feature-local widgets | `lib/features/<x>/ui/widgets/` |

Read a widget's source before reusing it — constructor parameters are its API; don't guess.

## Semantics identifier naming

Convention: **kebab-case**, `<feature>-<element>[-<qualifier>]`. Identifiers are internal test hooks — never localized.

| Element | Identifier |
|---|---|
| Primary CTA on a page | `items-filter` |
| Back button | `organization-selector-back` |
| Nth card in a list | `items-card-$index` |
| Text input | `organization-search-field` |
| Confirmation modal | `items-delete-confirm-modal` |
| Action inside that modal | `items-delete-confirm-dismiss` |
| Retry button on an error state | `items-retry` |

Rules of thumb:
- **List items always include the index** (`items-card-$index`) so a Maestro flow can target row N.
- **Group co-located actions** under a shared prefix (`items-delete-confirm-*` for everything inside that modal).
- **Identifiers are stable contracts.** Renaming one breaks Maestro flows under `.maestro/` — if you must rename, update the flows in the same change.
- **Skip purely decorative widgets** (icons, dividers, static text) — nothing to assert against.

## The four legitimate `StatefulWidget` cases

1. **Controllers needing `dispose`** — `TextEditingController`, `ScrollController`, `AnimationController`, `FocusNode`, `TabController`, `PageController`.
2. **Lifecycle observers** — `WidgetsBindingObserver.didChangeAppLifecycleState`, route observers.
3. **Pure UI-only state** — animation tween values, "is the password obscured", "is the menu expanded". The line: if it's not observable from outside this widget AND has no business meaning, it may stay local; otherwise it belongs in the cubit.
4. **Debounce timers** — a `Timer?` cancelled in `dispose`.

Even then: outer widget stays `StatelessWidget` (public API + `Semantics`), the stateful part is the smallest private inner body.

## Placement / promotion quick lookup

| What you're building | Where it lives |
|---|---|
| Header / row / section used once in one page | Private `_FooSection` in the page file |
| Widget needed by a second page of the same feature | `lib/features/<x>/ui/widgets/` |
| Widget genuinely used by ≥2 features, themed surface | `lib/core/widgets/` — promotion is a user decision |
| Widget for the auth fixed-gradient shell | feature-private, e.g. `lib/features/auth/ui/widgets/auth_shell/` |
| Text field for an input semantic (email/password/…) | Not a widget — a `FormzInput`; → `/form-creation` |

Extract a section out of the page file when it's a distinct visual unit past ~30 lines, or when it owns its own `BlocBuilder` slice (rule 2 — rebuild isolation). "Might be reused later" is not a reason to promote.
