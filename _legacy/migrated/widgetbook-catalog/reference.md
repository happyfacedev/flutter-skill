# Widgetbook Catalog — Token Reference

Detailed lookup tables for `SKILL.md`. Project-specific token names (and any overrides exported from the catalog) live in the sibling `tokens.skill-data.md`, regenerated on every catalog export.

## `context.colors.<role>` — theme-aware color roles

| Role | Light | Dark | Replaces |
|---|---|---|---|
| `primary` | teal500 | teal500 | brand primary |
| `primaryPressed` | teal700 | teal700 | pressed state |
| `primaryDisabled` | teal200 | gray750 | disabled background |
| `accent` | coral500 | coral500 | brand accent |
| `text` | gray950 | white | primary text |
| `hint` | gray500 | gray350 | secondary text |
| `background` | canvasLight | gray850 | scaffold background |
| `surface` | white | gray750 | card surface |
| `border` | gray150 | gray700 | default border |
| `divider` | gray200 | gray800 | divider |
| `buttonText` | white | white | text on primary button |
| `buttonTextDisabled` | gray450 | gray450 | disabled text |
| `errorText` | red500 | red300 | error text |
| `errorBackground` | red400 | red700 | error background |
| `successText` | green500 | green300 | success text |
| `successBackground` | green50 | green700 | success background |
| `warningText` | yellow500 | yellow300 | warning text |
| `warningBackground` | yellow50 | yellow900 | warning background |

## `context.styles.<role>` — typography roles

### Core (theme-aware color)

| Role | Size / Weight / Color |
|---|---|
| `pageTitle` | 28 / 600 / text.primary |
| `headlineMedium` | 24 / 600 / text.primary |
| `sectionHeader` | 20 / 600 / text.primary |
| `bodyLarge` | 16 / 400 / text.primary |
| `fieldText` | 16 / 400 / text.primary |
| `button` | 16 / 600 / text.primary |
| `subtitle` | 14 / 500 / text.primary |
| `linkText` | 14 / 700 / interactive.primary |
| `fieldError` | 13 / 400 / text.error |
| `caption` | 13 / 400 / text.secondary |
| `metaText` | 12 / 400 / text.secondary |
| `statusBadge` | 12 / 600 / text.primary |

### Auth/marketing (brand-fixed color — same in light + dark)

| Role | Size / Weight / Color |
|---|---|
| `authDisplayLarge` | 40 / 700 / white |
| `authDisplayMedium` | 30 / 700 / brandInk |
| `authDisplaySmall` | 28 / 700 / white |
| `authTitle` | 24 / 700 / white |
| `authSubtitle` | 17 / 400 / white@85 |
| `authButtonLabel` | 17 / 600 / white |
| `authInputText` | 17 / 500 / white |
| `authSocialLabel` | 16 / 600 / white |
| `authBody` | 15 / 400 / white@70 |
| `authNavLabel` | 15 / 500 / white@70 |
| `authLinkAccent` | 14 / 600 / brandTealGlow |
| `authLinkLeading` | 14 / 400 / white@65 |
| `authLinkInline` | 14 / 500 / brandTealGlow |
| `authMeta` | 13 / 400 / white@55 |
| `authTerms` | 12 / 400 / white@55 |
| `authTag` | 12 / 700 / caller-supplied |

## `context.spacing.<role>` — semantic spacing

| Role | Value |
|---|---:|
| `hairline` | 1 |
| `xs` | 4 |
| `row` | 6 |
| `sm` | 8 |
| `md` | 12 |
| `cardPadding` | 16 |
| `inputContent` | 16 |
| `authButtonV` | 17 |
| `authInputV` | 18 |
| `pagePadding` | 20 |
| `lg` | 24 |
| `authPagePadding` | 28 |
| `xl` | 32 |
| `section` | 40 |
| `xxl` | 48 |

## `context.radius.<role>` — semantic radii

| Role | Value | Used for |
|---|---:|---|
| `pinCell` | 10 | OTP input cells |
| `card` | 12 | Card surfaces |
| `button` | 14 | Auth buttons + inputs |
| `sheet` | 18 | Bottom sheets / inset surfaces |
| `iconTile` | 22 | 72×72 icon tiles |
| `input` | 50 | Pill-style input fields |
| `pill` | 999 | Fully rounded chips |

## `context.iconSize.<role>` — semantic icon sizes

| Role | Value |
|---|---:|
| `sm` | 20 |
| `md` | 24 |
| `lg` | 28 |

## `context.motion.<role>` — semantic motion

| Role | Value |
|---|---|
| `snap` | 150ms |
| `defaultDuration` | 200ms |
| `transition` | 350ms |
| `dramatic` | 500ms |
| `easingStandard` | `Cubic(0.6, 0.25, 0, 1.0)` |

## `AppColors.brand*` carve-out (theme-independent — static const)

Use these directly when the surface intentionally renders the same in light + dark (auth gradient, iOS-style success/error/warning chips).

| Constant | Hex |
|---|---|
| `brandTeal` | `#2F7874` |
| `brandTealLight` | `#4A9B96` |
| `brandTealSoft` | `#E8F3F2` |
| `brandTealGlow` | `#C5E2E0` |
| `brandCoral` | `#EA9280` |
| `brandCoralLight` | `#F0AFA2` |
| `brandCoralSoft` | `#FDF0ED` |
| `brandOlive` | `#A1A27F` |
| `brandMidnight` | `#1A1D2E` |
| `brandInk` | `#1C1C1E` |
| `brandSecondary` | `#636366` |
| `brandTertiary` | `#AEAEB2` |
| `brandSeparator` | `#E5E5EA` |
| `brandSeparatorLight` | `#F2F2F7` |
| `brandSuccess` | `#34C759` |
| `brandError` | `#FF3B30` |
| `brandWarning` | `#FF9500` |
| `authGradientColors` | 5-stop list |
| `authGradientStops` | `[0.0, 0.25, 0.45, 0.65, 1.0]` |

## `AppSize.<name>` legacy constants (static const — back-compat only)

Keep using inside `const EdgeInsets.all(...)` / `const SizedBox(...)`. **Don't** drop `const` to switch to `context.spacing.*` — that's a regression. New code should default to `context.spacing.*` instead.

Common values: `padding (16)`, `smallPadding (12)`, `largePadding (20)`, `xSmallPadding (6)`, `radius (12)`, `roundedRadius (50)`, `s4 / s8 / s12 / s16 / s20 / s24 / s32 / s48 / s64 / ...`, `iconSmall (20)`, `iconMedium (24)`, `iconSize (29)`, `authRadius (14)`, `authEdgePadding (28)`.

## Catalog file layout

```
lib/
├── main_catalog.dart                # entry point — runCatalog(...)
├── catalog_showcases/                # foundational showcase entries
│   ├── typography_showcase.dart
│   ├── colors_showcase.dart
│   ├── buttons_showcase.dart
│   ├── form_fields_showcase.dart
│   └── auth_surface_showcase.dart
└── features/<feature>/ui/catalog/   # feature-bound catalog entries (optional)
    └── <page>_catalog.dart

tools/design_catalog/                 # the catalog package itself (don't edit when adding screens)
└── lib/
    ├── design_catalog.dart           # public API barrel
    └── src/
        ├── tokens/                   # DesignTokens, ColorRole, TextRole, ThemeProvider
        ├── api/                      # CatalogEntry, CatalogCase, CaseContext, CatalogShell
        ├── state/                    # CatalogCubit
        ├── runner/                   # runCatalog
        ├── ui/                       # sidebar + matrix + token editor
        ├── url/                      # URL state codec
        └── export/                   # token export
```

## Running the catalog

```bash
flutter run -t lib/main_catalog.dart -d chrome
```

Visit `http://localhost:<port>/#/`. Pick a screen on the left, toggle devices/themes on the top bar, expand the token editor on the right.

## When you'd extend this reference

- After adding a new semantic role: add a row to the matching table here.
- After adding a new device preset: update `DevicePreset.builtIns` in the catalog AND add a note here.
- After expanding the catalog UI (new token-editor category): mention it in `SKILL.md`'s decision table.
