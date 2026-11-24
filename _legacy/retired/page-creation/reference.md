# Page Creation — Reference

Token catalogs and naming conventions. Source files live in `lib/core/theme/` — those are authoritative for current values. This page mirrors them in a quick-lookup format.

## Spacing — `AppSize`

Source: `lib/core/theme/sizes.dart`

**For new code, prefer the numeric `s*` constants.** The named aliases (`padding`, `smallPadding`, etc.) are kept for back-compat and the source file labels them "Legacy padding aliases (prefer using s* constants directly)."

### Numeric constants (preferred)

| Constant | Value | |
|---|---|---|
| `AppSize.s1` | 1 | |
| `AppSize.s2` | 2 | |
| `AppSize.s4` | 4 | |
| `AppSize.s6` | 6 | |
| `AppSize.s8` | 8 | |
| `AppSize.s10` | 10 | |
| `AppSize.s12` | 12 | |
| `AppSize.s14` | 14 | |
| `AppSize.s16` | 16 | |
| `AppSize.s18` | 18 | |
| `AppSize.s20` | 20 | |
| `AppSize.s22` | 22 | |
| `AppSize.s24` | 24 | |
| `AppSize.s28` | 28 | |
| `AppSize.s32` | 32 | |
| `AppSize.s36` | 36 | |
| `AppSize.s40` | 40 | |
| `AppSize.s42` | 42 | |
| `AppSize.s48` | 48 | |
| `AppSize.s52` | 52 | |
| `AppSize.s56` | 56 | |
| `AppSize.s58` | 58 | |
| `AppSize.s64` | 64 | |
| `AppSize.s70` | 70 | |
| `AppSize.s80` | 80 | |
| `AppSize.s96` | 96 | |
| `AppSize.s100` | 100 | |
| `AppSize.s117` | 117 | |
| `AppSize.s189` | 189 | |

### Named aliases (legacy — back-compat only)

| Constant | Equivalent |
|---|---|
| `AppSize.padding` | `s16` |
| `AppSize.largePadding` | `s20` |
| `AppSize.smallPadding` | `s12` |
| `AppSize.xSmallPadding` | `s6` |
| `AppSize.xxSmallPadding` | `s1` |

### Radii

| Constant | Value | Use |
|---|---|---|
| `AppSize.radius` | 12 | Standard card / input radius |
| `AppSize.roundedRadius` | 50 | Pill-shaped buttons / chips |
| `AppSize.authRadius` | 14 | Buttons + inputs on auth surfaces |
| `AppSize.authCardRadius` | 18 | Auth card / preview / inset surfaces |
| `AppSize.authIconTileRadius` | 22 | Auth icon tiles |

### Icons

| Constant | Value |
|---|---|
| `AppSize.iconSmall` | 20 |
| `AppSize.iconMedium` | 24 |
| `AppSize.iconSize` | 29 |

### Auth-surface specifics

| Constant | Value |
|---|---|
| `AppSize.authButtonVerticalPadding` | 17 |
| `AppSize.authInputVerticalPadding` | 18 |
| `AppSize.authEdgePadding` | 28 |

## Text styles — `context.styles`

Source: `lib/core/theme/styles.dart`. All styles run through the `.variable` extension internally (variable-font support) — consumers just use `context.styles.foo`.

### Core text styles

| Style | Size / Weight | Use |
|---|---|---|
| `context.styles.fieldText` | 16px / w400 | Input field text |
| `context.styles.fieldError` | 13px / w400 (error color) | Form validation errors |
| `context.styles.button` | 16px / w600 | Button labels |
| `context.styles.linkText` | 14px / w700 (underline, primary color) | Inline clickable links |
| `context.styles.pageTitle` | 28px / w600 | Top-most page heading |
| `context.styles.sectionHeader` | 20px / w600 | Card headers, section titles |
| `context.styles.headlineMedium` | 24px / w600 | Full-screen headings |
| `context.styles.bodyLarge` | 16px / w400 | Body paragraphs |
| `context.styles.subtitle` | 14px / w500 | Card subtitles, secondary labels |
| `context.styles.caption` | 13px / w400 (hint color) | Meta / helper text |
| `context.styles.metaText` | 12px / w400 (hint color) | Timestamps, counters, footnotes |
| `context.styles.statusBadge` | 12px / w600 | Status chip labels |

### Auth-surface styles (dark gradient unauth screens — theme-independent)

These override colors with explicit white/brand tones because auth surfaces render on the dark gradient regardless of user theme.

| Style | Size / Weight | Use |
|---|---|---|
| `context.styles.authDisplayLarge` | 40px / w700 | Splash hero |
| `context.styles.authDisplayMedium` | 30px / w700 | Intro slides, landing welcome |
| `context.styles.authDisplaySmall` | 28px / w700 | Login / Register / Forgot headlines |
| `context.styles.authTitle` | 24px / w700 | Confirmation states |
| `context.styles.authSubtitle` | 17px / w400 | Primary subtitle on dark gradient |
| `context.styles.authButtonLabel` | 17px / w600 | Primary button label |
| `context.styles.authInputText` | 17px / w500 | Input field text on dark gradient |
| `context.styles.authSocialLabel` | 16px / w600 | Landing social button labels |
| `context.styles.authBody` | 15px / w400 | Secondary subtitles on dark surfaces |
| `context.styles.authNavLabel` | 15px / w500 | Back / skip button labels |
| `context.styles.authLinkAccent` | 14px / w600 (teal accent) | Bottom switch link text |
| `context.styles.authLinkLeading` | 14px / w400 | Bottom switch leading text |
| `context.styles.authLinkInline` | 14px / w500 (teal accent) | Inline link ("Forgot password?") |
| `context.styles.authMeta` | 13px / w400 | Auth meta lines |
| `context.styles.authTerms` | 12px / w400 | Auth terms paragraph |
| `context.styles.authTag` | 12px / w700 (letterSpacing 1.2) | Intro carousel tags |

## Colors

Source: `lib/core/theme/colors.dart`.

### Theme-aware — `context.colors` (preferred)

These resolve to the right light/dark variant automatically.

| Group | Tokens |
|---|---|
| **Brand** | `primary`, `primaryPressed`, `primaryDisabled`, `accent`, `accentPressed`, `accentDisabled` |
| **Text** | `text`, `hint` |
| **Background** | `background`, `surface` |
| **Border** | `border`, `divider` |
| **Button** | `buttonText`, `buttonTextDisabled` |
| **Error** | `errorText`, `errorBackground` |
| **Success** | `successText`, `successBackground` |
| **Warning** | `warningText`, `warningBackground` |

### Static `AppColors.*` — when it's OK

Theme-independent static constants. Allowed when the surface renders the same regardless of theme:

- **Auth surfaces** (intentional dark gradient in light + dark mode):
  `authGradientColors`, `authGradientStops`, `brandMidnight`, `brandInk`, `brandTeal`, `brandTealLight`, `brandTealSoft`, `brandTealGlow`, `brandCoral`, `brandCoralLight`, `brandCoralSoft`, `brandOlive`

- **Universal**: `white`

- **Hairlines / chip backgrounds** used in JSX previews:
  `brandSecondary`, `brandTertiary`, `brandQuaternary`, `brandSeparator`, `brandSeparatorLight`, `brandBgSecondary`, `brandBgTertiary`

- **iOS-style status colors** when the design calls for the fixed iOS tone:
  `brandSuccess` (#34C759), `brandError` (#FF3B30), `brandWarning` (#FF9500)

If you find yourself reaching for a static `AppColors.brand*` because `context.colors` doesn't have the shade you need — that's usually a signal the theme is missing a token. Prefer adding the token to `context.colors` over normalizing on the static.

## BuildContext extensions

Source: `lib/core/theme/extensions.dart` and `lib/core/localization/localization_extension.dart`.

| Extension | Returns | Notes |
|---|---|---|
| `context.styles` | `AppStyles` | Text styles (see above) |
| `context.colors` | `AppColors` | Theme-aware colors (see above) |
| `context.isDark` | `bool` | `Theme.brightnessOf(context) == Brightness.dark` |
| `context.localization` | `AppLocalizations` | i18n — see `/localization-arb` |
| `16.vSpace` | `SizedBox(height: 16)` | Spacing extension on `num` |
| `12.hSpace` | `SizedBox(width: 12)` | Spacing extension on `num` |

The `.vSpace` / `.hSpace` extensions pair with `AppSize.*` cleanly: `AppSize.s16.vSpace` is equivalent to `const SizedBox(height: AppSize.s16)` but reads better in a `Column`.

## Semantics identifier naming

Convention: **kebab-case**, `<feature>-<element>[-<qualifier>]`. Identifiers are internal test hooks — do not localize them.

| Element | Identifier |
|---|---|
| Primary CTA on items page | `items-filter` |
| Back button on selector | `organization-selector-back` |
| Nth card in a list | `items-card-$index` |
| Text input | `organization-search-field` |
| Modal in error state | `items-delete-confirm-modal` |
| Action inside that modal | `items-delete-confirm-dismiss` |
| Dropdown | `item-detail-organization-dropdown` |
| Submit on auth form | `auth-submit` |
| Retry button on error state | `items-retry` |

Rules of thumb:
- **List items always include the index** (`items-card-$index`) so a Maestro flow can target row N.
- **Group co-located actions** under a shared prefix (`items-delete-confirm-*` for everything inside that modal).
- **Identifiers are stable contracts.** Renaming one breaks Maestro flows in `.maestro/`. If you must rename, update the flows in the same PR.
- **Skip purely decorative widgets** (icons, dividers, static text) — they have nothing to assert against.
