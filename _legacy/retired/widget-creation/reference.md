# Widget Creation — Reference

What already exists in `lib/core/widgets/` and `lib/core/design/` — search HERE before creating. Source files in those directories are authoritative on current API; this page is the lookup index by purpose.

## `core/widgets/` — generic, theme-aware

These use `context.colors` / `context.styles` and adapt to light/dark mode. Use on authenticated post-startup surfaces.

| Widget | File | Purpose |
|---|---|---|
| `MainButton` | `main_button.dart` | Primary CTA — 52px tall, rounded (50px radius), teal background, supports `transparent` outlined variant, `isLoading`, `semanticsIdentifier` |
| `BaseTextField` | `base_text_field.dart` | Plain text input (non-form) — wraps `TextField` with project's input decoration |
| `BaseFormTextField` | `base_form_text_field.dart` | Form-aware text input — accepts a `validator`, debounces validation (500ms default), pairs with `FieldErrorWidget` for animated error display. See `/form-creation`. |
| `LoadingWidget` | `loading_widget.dart` | Centered spinner with theme-aware color |
| `ErrorMessageWidget` | `error_message_widget.dart` | Inline error display with icon + retry slot |
| `FieldErrorWidget` | `field_error_widget.dart` | Animated below-field error text — used by `BaseFormTextField` |
| `AdaptiveScaffold` | `adaptive_scaffold.dart` | Scaffold variant for layouts that adapt across breakpoints |
| `ScaffoldWithNavBar` | `scaffold_with_nav_bar.dart` | Bottom-nav shell for the authenticated tab area — used by `StatefulShellRoute.indexedStack` |
| `BottomNavBar` | `bottom_nav_bar.dart` | The bottom nav itself (consumed by `ScaffoldWithNavBar`) |
| `LogoWidget` | `logo_widget.dart` | The app logo |
| `CustomAnimatedSwitcher` | `custom_animated_switcher.dart` | Cross-fade transition between child widgets |
| `PullToActionWrapper` | `pull_to_action_wrapper.dart` | Pull-to-refresh wrapper with custom action |
| `SettingsCard` | `settings_card.dart` | Card container for settings rows |
| `SettingsRow` | `settings_row.dart` | Single row inside a settings card |
| `ShellWrapper` | `shell_wrapper.dart` | Wrapper for shell-level overlays |
| `TappableWidget` | `tappable_widget/` | Tappable container with `TappableWidgetCubit` for press feedback — used internally by `MainButton` |
| Form inputs | `form_inputs/` (subfolder) | `FormzInput` subclasses — see `/form-creation` |

## `core/design/` — the `Ds*` family, theme-independent

Used on auth, intro, onboarding surfaces that render a fixed dark gradient regardless of user theme. Colors come from `AppColors.brand*` statics, not `context.colors`.

| Widget | File | Purpose |
|---|---|---|
| `DsScreen` | `ds_screen.dart` | Page wrapper — the dark gradient background + safe-area padding for auth/onboarding surfaces |
| `DsPrimaryButton` | `ds_primary_button.dart` | Primary CTA on auth surfaces — 60px tall, 14px radius, teal + drop shadow, 17/600 label |
| `DsGhostButton` | `ds_ghost_button.dart` | Secondary CTA on auth surfaces — outline / transparent variant |
| `DsHeader` | `ds_header.dart` | Page heading on auth surfaces (display-medium / display-large styles) |
| `DsSectionLabel` | `ds_section_label.dart` | Smaller section heading |
| `DsPillInput` | `ds_pill_input.dart` | Pill-shaped text input for auth forms |
| `DsUnderlineInput` | `ds_underline_input.dart` | Underline-only text input variant |
| `DsCheckboxRow` | `ds_checkbox_row.dart` | Checkbox + label row (e.g., terms acceptance) |
| `DsToggleRow` | `ds_toggle_row.dart` | Switch + label row |
| `DsChoiceChip` | `ds_choice_chip.dart` | Selectable chip — used in filters, choice pickers |
| `DsListCard` | `ds_list_card.dart` | Card row in a list — used in selector/picker screens |
| `DsSelectableCard` | `ds_selectable_card.dart` | Card with selected state, used in plan/option pickers |
| `DsBottomSheetModal` | `ds_bottom_sheet_modal.dart` | Bottom-sheet container with rounded top + drag handle |
| `DsStepProgress` | `ds_step_progress.dart` | Multi-step progress indicator — used in onboarding |
| `design.dart` | (barrel) | Exports the whole family — `import 'package:core_boilerplate/core/design/design.dart';` |

## Quick decision lookup

| What you're building | Where it lives |
|---|---|
| A header / footer / row used once in one page | Private `_FooSection` `StatelessWidget` inside the page file |
| An item card used by `ItemsPage` and `HomePage` (same feature) | `lib/features/items/ui/widgets/item_card.dart` |
| A button used across multiple features on authenticated screens | Promote to `lib/core/widgets/` (existing or new) |
| A button on the login screen | Use `DsPrimaryButton` from `core/design/` |
| A new theme-independent visual specific to auth/onboarding | New `lib/core/design/ds_<name>.dart` |
| A new theme-aware visual specific to authenticated screens | New `lib/core/widgets/<name>.dart` |
| A text field for a specific input semantic (email / password / phone) | NOT a widget — that's a `FormzInput`. See `/form-creation` |
| A form field that renders the input visually | Use existing `BaseFormTextField` with your `FormzInput`'s validator |

## When `StatefulWidget` is justified inside a widget

Default is `StatelessWidget`. The four legitimate reasons to reach for `StatefulWidget`:

1. **Controllers needing `dispose`** — `TextEditingController`, `ScrollController`, `AnimationController`, `FocusNode`, `TabController`, `PageController`.
2. **Lifecycle observers** — `WidgetsBindingObserver.didChangeAppLifecycleState`, route observer callbacks.
3. **Pure UI-only state** that doesn't belong in a cubit — animation tween values, "is the password obscured", "is the dropdown open". The line between this and "belongs in a cubit": if it's not observable from outside this widget AND it has no business meaning, keep it local with `StatefulWidget`.
4. **Debounce timers** — `Timer?` that needs to be cancelled in `dispose` (see `BaseFormTextField` for this exact pattern).

When `StatefulWidget` is required, the outer widget should still be `StatelessWidget` and delegate to the smallest possible inner stateful piece. See `MainButton` / `_MainButtonBody` in `core/widgets/main_button.dart` for the canonical split.
