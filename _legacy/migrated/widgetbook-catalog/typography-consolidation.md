# Typography Consolidation Spec

Reduces the project's typography roles from ~70 to **17 canonical roles** (industry standard band: M3 = 15, Carbon = 16-23, iOS HIG = 11). Used by:

- `business-logic-expert` agent migrating call sites.
- `widgetbook-catalog` use-case authors writing new code.
- Anyone editing `lib/core/theme/styles.dart`, `tools/design_catalog/lib/src/tokens/semantic/semantic_typography.dart`, or `lib/core/theme/tokens/baseline.dart`.

## Rules

1. **NO `.copyWith(fontSize: …)`** — ever. If you need a different size, pick a different role.
2. **NO `.copyWith(height: …)`** — ever. Each canonical role has ONE line-height baked in for its intended use; if you need a different height, you're in a different role.
3. **`.copyWith(fontWeight: …)` IS allowed** — for emphasis bumps (R → M → Sb → B) at the same size.
4. **`.copyWith(color: …)` IS allowed** — for tinting at the same size/weight/height.
5. **`.copyWith(letterSpacing: …)` is allowed** — rare, but legal.
6. **`backgroundColor`/`decoration*` MUST NOT be touched at callsites** — the catalog uses those for the highlight overlay; touching them defeats the marker.
7. **For "white text on auth gradient" surfaces**, wrap the subtree in `DefaultTextStyle.merge(style: TextStyle(color: Colors.white))` at the page level. Individual `Text` widgets then use the canonical role; the white color cascades. Where alpha is needed (e.g. 70% white for body), use `.copyWith(color: Colors.white.withOpacity(0.7))`.

## The 17 canonical roles

| # | Role | Size | Weight | Height | Tracking | Default color | Primary use |
|---|------|------|--------|--------|----------|---------------|-------------|
| 1 | `displayLarge` | 40 | Bold | 1.10 | -0.8 | textPrimary | Hero number (auth, very-large metric) |
| 2 | `displayMedium` | 32 | Bold | 1.10 | -0.96 | interactivePrimary | Big metric (intro carousel) |
| 3 | `displaySmall` | 28 | Bold | 1.18 | -0.56 | textPrimary | Page hero (home greeting, auth display) |
| 4 | `headlineLarge` | 24 | Bold | 1.21 | -0.48 | textPrimary | Detail screen heading, auth title |
| 5 | `headlineMedium` | 22 | Bold | 1.21 | -0.44 | textPrimary | In-app page header ("Cursuri", "Profil") |
| 6 | `headlineSmall` | 20 | Sb | 1.21 | 0 | textPrimary | Section header within page |
| 7 | `titleLarge` | 18 | Bold | 1.10 | -0.36 | textPrimary | List-row leading time, card title |
| 8 | `titleMedium` | 16 | Sb | 1.21 | 0 | textPrimary | Button label, strong inline label |
| 9 | `titleSmall` | 14 | Sb | 1.21 | 0 | textPrimary | List-card title, class name |
| 10 | `bodyLarge` | 16 | R | 1.50 | 0 | textPrimary | Paragraph 16pt (descriptions, modals) |
| 11 | `bodyMedium` | 14 | R | 1.50 | 0 | textPrimary | Paragraph 14pt |
| 12 | `bodySmall` | 13 | R | 1.40 | 0 | textSecondary | Caption paragraph, hint |
| 13 | `labelLarge` | 12 | Sb | 1.21 | 0 | textPrimary | Status badge, chip text |
| 14 | `labelMedium` | 12 | R | 1.21 | 0 | textSecondary | Small meta, list secondary |
| 15 | `labelSmall` | 11 | M | 1.21 | 0 | textTertiary | Weekday short, dense sub-label |
| 16 | `overline` | 12 | Sb | 1.21 | 1.2 | textPrimary | Wide-tracked eyebrow ("URMĂTORUL CURS · ÎN 48 MIN") |
| 17 | `fieldText` | 16 | R | 1.21 | 0 | textPrimary | Text input field content (NOT for paragraphs — use bodyLarge) |
| 18 | `fieldError` | 13 | R | 1.21 | 0 | textError | Form field error message |

That's actually 18 (17 + fieldError as a distinct color-baked role). Acceptable.

## Migration map (old → new)

### Display

| Old | New | Action |
|-----|-----|--------|
| `displayMedium` (32/B/1.10) | `displayMedium` | No change |
| `displayMediumTight` (32/B/1.0) | `displayMedium` | Drop role; line-height becomes 1.10 |
| `displaySmall` (28/B/1.18) | `displaySmall` | No change |

### Headline

| Old | New | Action |
|-----|-----|--------|
| `headlineLarge` (24/B/1.21) | `headlineLarge` | No change |
| `headlineLargeTight` (24/B/1.0) | `headlineLarge` | Drop role; height becomes 1.21 |
| `headlineMedium` (22/B/1.21) | `headlineMedium` | No change |
| `headlineMediumSemibold` (22/Sb/1.21) | `headlineMedium.copyWith(fontWeight: w500)` | weight copyWith |
| `headlineMediumSemiboldTight` (22/Sb/1.25) | `headlineMedium.copyWith(fontWeight: w500)` | drop tight variant |
| `headlineSmall` (20/Sb/1.21) | `headlineSmall` | No change |
| `headlineSmallBold` (20/B/1.10, interactivePrimary) | `headlineSmall.copyWith(fontWeight: w700, color: context.colors.primary)` | weight + color copyWith; accept 1.10→1.21 drift |
| `headlineSmallBoldSnug` (20/B/1.20) | `headlineSmall.copyWith(fontWeight: w700)` | Drop variant |

### Title

| Old | New | Action |
|-----|-----|--------|
| `titleLarge` (18/B/1.10) | `titleLarge` | No change |
| `title17Bold` (17/B/1.10) | `titleLarge` | Drop role; 17→18 visual drift |
| `titleMedium` (16/Sb/1.21) | `titleMedium` | No change |
| `titleMediumBold` (16/B/1.21) | `titleMedium.copyWith(fontWeight: w700)` | weight copyWith |
| `titleSmall` (14/M/1.21) | `titleSmall.copyWith(fontWeight: w500)` | titleSmall is now Sb-default; weight bump down for legacy sites |
| `titleSmallSemibold` (14/Sb/1.21) | `titleSmall` | Becomes the new default |

### Body

| Old | New | Action |
|-----|-----|--------|
| `bodyLarge` (16/R/1.21) | `fieldText` | bodyLarge becomes 1.50; UI/compact 1.21 callsites move to fieldText |
| `bodyLargeBody` (16/R/1.50) | `bodyLarge` | Now the canonical |
| `bodyLargeBodyLoose` (16/R/1.55, secondary) | `bodyLarge.copyWith(color: context.colors.textSecondary)` | Drop variant; height 1.55→1.50 drift |
| `body15` (15/R/1.21) | `bodyMedium` | 15→14 size drift accepted |
| `body15Medium` (15/M/1.21, secondary) | `bodyMedium.copyWith(fontWeight: w500, color: secondary)` | weight + color |
| `body15Semibold` (15/Sb/1.21) | `bodyMedium.copyWith(fontWeight: w600)` | weight |
| `body15Bold` (15/B/1.21) | `bodyMedium.copyWith(fontWeight: w700)` | weight |
| `body15Relaxed` (15/R/1.4) | `bodyMedium` | Drop variant |
| `body15Body` (15/R/1.5) | `bodyMedium` | Drop variant |
| `body15BodyLoose` (15/R/1.6) | `bodyMedium` | Drop variant |
| `bodyMedium` (14/R/1.21) | `bodyMedium` | Height 1.21→1.50 drift |
| `bodyMediumBody` (14/R/1.5) | `bodyMedium` | Now canonical |
| `bodyMediumRelaxed` (14/R/1.4) | `bodyMedium` | Drop variant |
| `bodyMediumLoose` (14/R/1.45) | `bodyMedium` | Drop variant |
| `bodySmall` (13/R/1.21, secondary) | `bodySmall` | Now 1.40, slight drift |
| `bodySmallBody` (13/R/1.5) | `bodySmall` | Drop variant |
| `bodySmallMedium` (13/M/1.21) | `bodySmall.copyWith(fontWeight: w500, color: textPrimary)` | weight + color |
| `bodySmallSemibold` (13/Sb/1.21) | `bodySmall.copyWith(fontWeight: w600, color: textPrimary)` | weight + color |

### Label

| Old | New | Action |
|-----|-----|--------|
| `labelLarge` (12/Sb/1.21) | `labelLarge` | No change |
| `labelMedium` (12/R/1.21, secondary) | `labelMedium` | No change |
| `labelMediumRelaxed` (12/R/1.4) | `labelMedium` | Drop variant |
| `labelMediumBody` (12/R/1.5) | `labelMedium` | Drop variant |
| `labelXSmall` (11/R/1.21, tertiary) | `labelSmall.copyWith(fontWeight: w400)` | 11pt drops weight to R via copyWith |
| `labelXSmallSnug` (11/R/1.3) | `labelSmall.copyWith(fontWeight: w400)` | Drop variant |
| `labelXSmallMedium` (11/M/1.21) | `labelSmall` | Now the canonical 11pt M |
| `labelXSmallSemibold` (11/Sb/1.21) | `labelSmall.copyWith(fontWeight: w600)` | weight |
| `labelXSmallBold` (11/B/1.21, tracking 0.55) | `labelSmall.copyWith(fontWeight: w700, letterSpacing: 0.55)` | weight + spacing |
| `labelSmall` (10/Sb/1.21) | `labelSmall` | Was 10pt, now 11pt — drift |
| `labelTiny` (9/B/1.21) | `labelSmall.copyWith(fontWeight: w700)` | 9→11 drift; very rare |

### Specialty

| Old | New | Action |
|-----|-----|--------|
| `overline` (12/Sb/1.21, tracking 1.2) | `overline` | No change |
| `button` (16/Sb/1.21) | `titleMedium` | Identical specs; drop role |
| `button15` (15/Sb/1.21) | `titleMedium` | Drop |
| `fieldText` (16/R/1.21) | `fieldText` | No change |
| `fieldTextSnug` (16/M/1.3) | `fieldText.copyWith(fontWeight: w500)` | weight copyWith |
| `fieldError` (13/R/1.21, error) | `fieldError` | No change |
| `linkText` (14/B/1.21, primary) | `titleSmall.copyWith(fontWeight: w700, color: context.colors.primary)` | drop role; weight + color |

### Auth (all migrate to canonical + color copyWith)

The auth surfaces wrap their content trees in `DefaultTextStyle.merge(style: TextStyle(color: Colors.white))` at the page root. Then:

| Old | New | Action |
|-----|-----|--------|
| `authDisplayLarge` (40/B/1.10, white) | `displayLarge` | Inherits white from `DefaultTextStyle` |
| `authDisplayMedium` (30/B/1.12, ink) | `displayMedium.copyWith(color: context.colors.brandInk)` | 30→32 drift |
| `authDisplaySmall` (28/B/1.15, white) | `displaySmall` | Inherits white |
| `authTitle` (24/B/1.20, white) | `headlineLarge` | Inherits white |
| `authSubtitle` (17/R/1.5, alpha-white-85) | `bodyLarge.copyWith(color: Colors.white.withOpacity(0.85))` | 17→16 drift |
| `authButtonLabel` (17/Sb/1.20, white) | `titleMedium` | 17→16 drift; inherits white |
| `authInputText` (17/M/1.20, white) | `fieldText.copyWith(fontWeight: w500)` | 17→16; weight copyWith |
| `authSocialLabel` (16/Sb/1.20, white) | `titleMedium` | Inherits white |
| `authBody` (15/R/1.5, alpha-white-70) | `bodyMedium.copyWith(color: Colors.white.withOpacity(0.7))` | 15→14 drift |
| `authBodyLarge` (16/R/1.45, alpha-white-70) | `bodyLarge.copyWith(color: Colors.white.withOpacity(0.7))` | 1.45→1.50 drift |
| `authNavLabel` (15/M/1.20, alpha-white-70) | `titleSmall.copyWith(fontWeight: w500, color: Colors.white.withOpacity(0.7))` | 15→14 drift |
| `authLinkAccent` (14/Sb/1.20, tealGlow) | `titleSmall.copyWith(color: context.colors.brandTealGlow)` | |
| `authLinkLeading` (14/R/1.20, alpha-white-65) | `titleSmall.copyWith(fontWeight: w400, color: Colors.white.withOpacity(0.65))` | weight bump |
| `authLinkInline` (14/M/1.20, tealGlow) | `titleSmall.copyWith(fontWeight: w500, color: context.colors.brandTealGlow)` | |
| `authMeta` (13/R/1.4, alpha-white-55) | `bodySmall.copyWith(color: Colors.white.withOpacity(0.55))` | |
| `authTerms` (12/R/1.5, alpha-white-55) | `labelMedium.copyWith(color: Colors.white.withOpacity(0.55))` | 1.5→1.21 drift |
| `authTag` (12/B/1.20, tracking 1.2, no color) | `overline.copyWith(fontWeight: w700)` | weight bump from Sb to B |

## Files to update

### Phase 1 — token plumbing

- `tools/design_catalog/lib/src/tokens/semantic/semantic_typography.dart` — delete all dropped fields from `SemanticTypography` (the variant roles), update `copyWith`, `==`, `hashCode`.
- `lib/core/theme/tokens/baseline.dart` — delete all dropped role definitions inside `semanticTypography = SemanticTypography(...)`. Update the 17 retained roles to the spec values.
- `lib/core/theme/styles.dart` — delete all dropped getters; verify the 17 retained getters match the spec.
- `tools/design_catalog/lib/src/tokens/typography_hierarchy.dart` — delete the entire `kTypographyParents` map (no variants anymore) AND remove all variant role cases from `lookupTypographyRole`. The hierarchy file becomes mostly stubs.
- `tools/design_catalog/lib/src/tokens/highlight.dart` — delete all dropped roles from `_replaceRole` and `_swapTypographyRole` switches.
- `tools/design_catalog/lib/src/ui/layout/token_editor_panel.dart` — delete dropped roles from the `_allTypographyRoles` list and the highlight tab's `typographyRoles` list.
- `tools/design_catalog/lib/src/export/token_export.dart` (if it lists role names) — sync.

### Phase 2 — call sites

Use `grep -rn 'context\.styles\.\(displayMediumTight\|headlineLargeTight\|...\)' lib` to find sites, then rewrite per the migration map.

Add `displayLarge` as a new role (40/B/1.10) — it doesn't exist today.

### Phase 3 — verification

- `cd tools/design_catalog && dart analyze`
- `cd lib && dart analyze` (project root)
- `dart run build_runner build --delete-conflicting-outputs`
- `flutter run -t lib/main_catalog.dart -d chrome --web-port 7654` — manually verify 5 representative tiles (splash, landing, home, classes, more).

## How agents should reach for this

- **`business-logic-expert` migrating call sites**: read this file before touching any feature page. The migration map is exhaustive — if you encounter a `context.styles.X` that isn't in the table, STOP and ask.
- **Use-case authors / widgetbook-catalog skill consumers**: only reference the 17 canonical roles. The variants are gone; do not use them in new code.
- **JSX-audit / new-screen authors**: same — only canonical roles. Inline `TextStyle()` is still forbidden by the widgetbook-catalog skill.
