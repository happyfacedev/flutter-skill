---
name: design-codify
description: Manual command — run ONLY when the user explicitly invokes /design-codify. Never auto-trigger. (Convert a locked design spec into Flutter theme, token, and core-widget files.)
---

# Design Codify — spec → Flutter

Converts a **locked** design produced by `/design-style` into the project's design-system code: token primitives, semantic token classes as theme extensions, `BuildContext` extensions, the app-wide `ThemeData`, font wiring, and the core widget inventory. After this skill runs, the code is the single source of truth and `/ui` consumes it forever; the spec remains as the decision record.

## Inputs

Two artifacts from `/design-style`, read together:

- **`design/tokens.json`** — W3C-DTCG shaped (`$value`/`$type`, aliases). This is the **PRIMARY token source**: transform it into Dart, **never re-derive token values from the spec prose**. If it is missing or out of parity with the spec's token section (§4), **stop** and send the user back to `/design-style`.
- **`design/DESIGN_SPEC.md`** — the decision record, **authoritative on any conflict**. Reconcile every tokens.json ↔ spec conflict back into *both* the spec and tokens.json before generating a line of code.

Component state **values** come from the spec's component section (§6); where a cell defers to an artifact, from `design/system_gallery.html` / the approved option sheets (the spec still wins on conflict). Read the **Invariants & usage rules** section (§5): every invariant becomes either an API constraint inside a widget or a written rule in the generated theme's doc header — usage rules a token can't express don't get dropped.

**Gate: refuse to run while any spec entry is `UNDECIDED` or `PROPOSED`.** Codifying an undecided spec bakes improvisation into the foundation — send the user back to `/design-style` with the list of open items. Small later amendments follow the same path: decide in the spec first, then re-codify the affected group.

## Target architecture

The kit-standard shape (core_boilerplate is the reference implementation — mirror its structure where the project already has one):

```
Decision (name · §hint)       →  Code home
────────────────────────────────────────────────────────────────
platform bias (§2)         →  the widget base (Material / Cupertino / custom)
                              and its exceptions list — read FIRST; it shapes
                              everything below
color primitives (§4.1)    →  primitives file (raw ramps, private)
color semantic (§4.1)      →  AppColors (light+dark resolution per role)
typography (§4.2)          →  AppStyles (composite roles; fonts in pubspec)
spacing (§4.3)             →  SemanticSpacing (gaps/paddings/sections + hairline)
shape & borders (§4.4)     →  SemanticRadius (+ border widths)
elevation (§4.5)           →  elevation roles (shadows light / surface-lightness dark)
icon sizes (§4.6)          →  SemanticIconSize
motion (§4.7)              →  SemanticMotion (durations + curves)
data-viz palettes (§4.8)   →  chart token class (chart.series1..n + grid / axis /
                              crosshair / tooltip roles); chart + map theming
signature & gradients (§4.9) → a gradient token (stops/angle, light+dark) OR an
                              asset OR — when the signature is programmatic — a
                              CustomPainter motif + animation driver reading token
                              roles. Do NOT assume gradient-or-asset. Map surfaces
                              get a style asset (e.g. assets/map/dark_style.json)
                              derived from the neutral ramp; the map/chart package
                              choice is recorded in the spec (route back to
                              /design-style if it's genuinely a design decision).
                              Illustration/photo assets ship with container +
                              fallback widgets
voice & microcopy          →  generated copy constants/patterns consumed by the
                              empty / error / permission-priming widgets
platform surfaces (§2)     →  icon/splash/native config notes + SystemUiOverlayStyle
                              + a haptic wrapper reading the spec's haptics policy
all theme-varying groups   →  ThemeExtension subclasses registered in ThemeData +
                              BuildContext sugar: context.colors / styles / spacing /
                              radius / iconSize / motion / chart
components (§6)             →  lib/core/widgets/ — ONE family, plain names
                              (PrimaryButton, PillInput; name collides with a
                              Flutter class → descriptive alternative, never a
                              prefix). Every component reads context.* tokens;
                              fixed-look surfaces (auth gradient) keep their
                              widgets feature-private under the static carve-out
```

Primitives are private to the theme layer — product code (and `/ui`) only ever sees the `context.*` semantic surface.

## Critical rules

1. **Codify in spec order: tokens → theme extensions → fonts → ThemeData → widgets.** *Why:* widgets are built exclusively from tokens; generating them first guarantees literals sneak in as placeholders and never leave.

2. **Every semantic color role gets its light AND dark value in the same definition** (when the spec supports both modes). *Why:* the spec decided both; deferring dark is how "we'll add dark mode later" becomes a rewrite. Theme-independent surfaces — declared by the **light/dark strategy** decision, not invented here — keep static tokens deliberately; that's the two-family split `/ui` enforces.

3. **Theme resolution is `ThemeExtension`, not static classes.** Any token group whose values vary by theme MUST be a `ThemeExtension<T>` subclass (with `copyWith`/`lerp`) registered in `ThemeData.extensions` and resolved via `Theme.of(context)`; `context.colors` is sugar over that extension lookup. Reserve static token classes for genuinely theme-independent values only. *Why:* the static shortcut "works" while the app is dark-only, then turns building the light theme the spec already planned into the exact rewrite rule 2 exists to prevent.

4. **Token names come from the spec verbatim** — role names, not values, per the naming rules already applied there. *Why:* the spec is the decision record; renaming during codification silently breaks traceability between the spec, the code, and future `/design-style` amendments.

5. **Core widgets constrain, don't expose.** Variant selection via enums (`AppButtonVariant.primary`), structure via slots (leading/title/trailing) — **never** raw `Color`, `TextStyle`, or numeric params that let a caller step outside the system. *Why:* Material widgets are maximally configurable by design; a design-system widget exists to *remove* configurability. An open `color:` param on `AppButton` re-opens every decision the spec just closed. Escape hatches, where truly needed, are named and deliberate (a `dangerouslyCustomStyle` reads as the warning it is).

6. **Every widget ships with all states the spec decided** — pressed/disabled/loading inside buttons, the full input-state row inside fields, the four data states where the component owns async content. *Why:* a button without a loading state forces every feature to improvise one; states are where systems erode first.

7. **Widgets follow the `/ui` contract:** `semanticsIdentifier` hoisted on every interactable, `StatelessWidget` outer + smallest stateful body, `const` constructors, one class per file, barrel exports where a family exists. *Why:* codified widgets are the most-reused code in the app — they set the pattern everything else copies.

8. **No literals anywhere in generated widget code** — every color, size, radius, duration reads from the token classes just generated. *Why:* the codifier is the one author with zero excuse; a literal here licenses literals everywhere. **Reconcile before generating:** diff every component value in spec §6 against the token set — a value with no token is either a **new token** (route back to `/design-style`) or a **named private component constant citing the spec's sanctioned exception** (`static const _tabLabelSize = 10.0; // spec §6: sanctioned exception`). "No literals" means no *inline* magic numbers; never force a sanctioned value onto the nearest-looking token to fake compliance. Self-check: grep for `Color(0x`, `fontSize:`, raw-number `EdgeInsets`, `Duration(milliseconds:` outside the token files.

9. **Every custom control re-implements the accessibility semantics Material would have supplied free.** `toggled` (switch/checkbox), slider semantics + value (slider/stepper), `button`, `header` (titles/section headers), `liveRegion` (toasts/banners). `semanticsIdentifier` is a **test hook, not a screen-reader role** — both are required, on every control. *Why:* a fully-custom kit built from `GestureDetector` + `Container` ships silently inaccessible; this is the uncaptured cost of the custom platform-bias decision.

## HTML → Flutter translation

The spec's approved visuals are browser artifacts; Flutter renders through its own engine and **never matches a browser pixel-for-pixel**. Sub-pixel text anti-aliasing differences are expected noise — don't chase them. The *real* deltas are closed-form and must be converted deterministically, never eyeballed:

| From the approved CSS | Generate in Flutter | Trap avoided |
|---|---|---|
| lengths / `font-size` in px | same number (logical px are CSS px, 1:1) | don't scale by devicePixelRatio |
| `line-height: 1.5` (unitless) | `height: 1.5` **+ `leadingDistribution: TextLeadingDistribution.even`** on every style | Flutter's default leading split differs from CSS half-leading AND differs between iOS and Android — `even` matches the browser and kills the platform split |
| `line-height: 24px` | `height: 24 / fontSize` | passing 24 raw |
| `letter-spacing: 0.02em` | `letterSpacing: 0.02 * fontSize` | passing the em number raw (it's logical px in Flutter) |
| `text-transform: uppercase` | no `TextStyle` equivalent — uppercase the **string** inside the `AppText`/role widget | reaching for a nonexistent style flag, or upper-casing at call sites where it can be skipped |
| `font-variant-numeric: tabular-nums` / `'tnum'` | `fontFeatures: [FontFeature.tabularFigures()]` | both this and uppercase belong **inside the mandated text-role widget** so no call site can bypass them |
| `box-shadow` blur `B` | `blurRadius = (B/2 − 0.5) / 0.57735 ≈ 0.866·B − 0.87` (offset/spread 1:1) | Flutter's `sigma = 0.57735·r + 0.5` vs CSS `σ = B/2`; the ×0.87 shorthand is fine for large blurs, **wrong for hairline ones** |
| multiple `box-shadow`s | `List<BoxShadow>` **reversed** | CSS paints the first shadow on top; Flutter paints it underneath |
| `inset` shadow | no true equivalent — `// TODO` + nearest approximation | assuming it maps |
| `cubic-bezier(a,b,c,d)` | `Cubic(a,b,c,d)` — raw numbers, 1:1 | ALL standard CSS keywords (`ease`/`ease-in`/`ease-out`/`ease-in-out`/`linear`) coincide with the same-named `Curves.*` — but **copy the raw bezier anyway**; a custom `cubic-bezier` has no named curve |
| colors | sRGB hex 1:1; opacity via `.withValues(alpha:)` (never deprecated `withOpacity`) | a design approved on a wide-gamut (P3) display reads duller in Flutter's sRGB — warn the user; offer `Color.from(... displayP3)` on iOS-first products if it matters |
| rounded corners, **solid fill only** | `BoxDecoration(borderRadius:)` — does NOT clip children | fine only when nothing inside reaches the corner |
| rounded corners, **child content reaches the radius** (media/map cards, avatars, image thumbnails, chart area fills) | `ClipRRect(clipBehavior: Clip.antiAliasWithSaveLayer)` | `antiAliasWithSaveLayer` kills the AA seam the old paint-don't-clip rule feared; a plain `BoxDecoration` lets child content square off the corner |
| `linear-gradient(θ, stops…)` | `LinearGradient(begin:, end:, colors:, stops:)`; direction `d = (sin θ, −cos θ)`, `begin = center − d`, `end = center + d` in `Alignment` space; stops 1:1 | axis-aligned angles are exact; **arbitrary angles on a non-square box** use CSS "corner-magic" Flutter can't reproduce — flag those, don't silently ship them |

Precise multiline box-height matching may additionally need `StrutStyle(forceStrutHeight: true)` alongside `height` + `leadingDistribution` — the strut pins every line box to the same height regardless of per-run font metrics.

## ThemeData assembly

Build one app-wide `ThemeData` (light and dark) so stock Material never leaks through the custom kit — even a fully-custom app still renders `Scaffold`, `TextField`, dialogs, scrollbars, and text selection; un-themed, they leak Material blue, ink ripples, teal selection handles, overscroll glow, and Roboto. Wire, from the tokens:

- **`ColorScheme`** derived from the semantic color roles (seed or explicit) so Material-owned surfaces resolve to the palette.
- **`splashFactory`** — `NoSplash.splashFactory` unless the spec's pressed treatment defines a ripple.
- **`TextSelectionThemeData`** — cursor, selection, and handle colors from the accent role.
- **scrollbar theme** + a **`ScrollBehavior`** that fixes overscroll and physics per the **platform-bias** decision.
- **`fontFamily`** + a full `textTheme` mapped from the type roles.
- app-wide **`SystemUiOverlayStyle`** and **`keyboardAppearance`** matching the active theme.

## Fonts

Bundle fonts under `assets/fonts/` (bundling beats runtime fetching for production determinism). **The wiring differs by font type:**

- **Variable font:** bundle **ONE** file and declare it **once** in `pubspec.yaml` — no per-weight entries. Then set **every non-default axis per role** via `fontVariations: [FontVariation('wght', …), FontVariation('wdth', …)]` (`wdth` is fully supported; still set `fontWeight` too, for fallback metrics). The VF silent-drift trap is a **missing `fontVariations`** — the glyphs render at the default instance, so a condensed hero silently becomes normal width. It is NOT a missing weight declaration.
- **Static family:** declare **every weight the design uses** in `pubspec.yaml` — a missing weight falls back silently with no warning. This declare-every-weight rule applies to static families only.

Verify licensing allows app embedding (the **typography** decision recorded the family; flag if the license question was skipped).

## MediaQuery policies

The custom kit owns the accessibility responses Material would otherwise handle:

- **Text scaling** — the mandated text-role widget clamps `MediaQuery.textScalerOf(context)` per role from the spec's scaling table: fixed roles clamp to `1.0`, scaling roles to their recorded cap. Clamping lives in the role widget so no call site can opt out.
- **Reduced motion** — motion honors `MediaQuery.disableAnimationsOf(context)`: movement swaps to a cross-fade, feedback is **never deleted** (a disabled animation must still confirm the action happened).
- **Don't invent silent policies.** Where the spec is silent, codify does NOT improvise — **haptics mapping, focus rendering on non-text controls, orientation/tablet behavior, and RTL** each route back to `/design-style` as a design decision, not a codifier default.

## The gallery route — the parity surface

Codify's last generated artifact is a hand-rolled debug route (`/gallery`, debug builds only): color roles as swatches with hex + role name, the full type ramp rendered with each role's size/height/tracking, spacing and radius scales, elevation samples, and **every core widget in every state** — including a long-text variant and a small-width variant, the two edge cases every handoff drops. This one screen is how a human verifies theme ↔ mock parity, and it permanently surfaces the states that would otherwise silently not exist.

## Verification

- **Throwaway-golden vision loop** (per widget family + each rebuilt north-star screen): generate a *throwaway* golden run with `autoUpdateGoldenFiles=true` → render the widget to PNG → **read the PNG yourself** and compare it against the corresponding `design/north_star.html` / `design/system_gallery.html` screenshot for layout, type, color, and spacing → iterate → **delete the throwaway**. Vision misses fine detail, so **back every pass with deterministic assertions pulled from `tokens.json`** — exact hex, border widths, radii.
- **Permanent goldens only for stable atoms** (buttons, the type ramp), and only with a **tolerant comparator** + a `FontLoader` loading the **real bundled font**, through a single canonical golden host. The defaults — exact-match comparison + the Ahem test font — guarantee false failures; never pixel-compare full screens against browser renders.
- Still do the **on-device side-by-side** of the gallery + rebuilt north-star against `design/north_star.html`; visual comparison reliably **misses 1px borders and shadow blur/spread** — re-check those numerically against `tokens.json`.

## Enforcement

**Mandatory minimum — a presubmit/CI check** that fails on `Color(0x`, `Colors.`, raw `TextStyle(`, and numeric `EdgeInsets` **outside the token/theme files**. Extended to the token files, the same check **backstops the handover rule**: a `tokens.json` diff that doesn't coincide with a `DESIGN_SPEC.md` diff fails the build (the record can't silently drift from the code). This is not optional — a token system erodes the moment a literal slips through unchecked.

Offer, don't impose:

- **Lint enforcement** — `leancode_lint`'s `use_design_system_item` (via `custom_lint`) forbids raw `Text`/`Colors.*` in favor of the generated components. Worth proposing on projects with more than one contributor.
- **Widgetbook + golden tests** — catalog each core widget × variants × states × light/dark; route to the widgetbook pattern when it lands.
- **Skeletonizer** — derives skeletons from real layouts if the spec's loading policy chose skeletons.

## Process

1. **Read the inputs by NAME.** Read the spec end to end, referring to decisions by name (platform bias, typography, light/dark strategy, data-viz language, signature element, platform surfaces …). Load `design/tokens.json` and confirm parity with spec §4 (missing/out-of-parity → stop, back to `/design-style`). Pull component values from §6 (+ `system_gallery.html` / option sheets where a cell defers). Read the **Invariants (§5)** — each becomes an API constraint or a doc-header rule. Verify the gate (all LOCKED/N/A) and **resolve every SUPERSEDED chain to its final entry**. Read **platform bias** first — it fixes the widget base and its exceptions list. **On a re-codify run:** scan the spec for SUPERSEDED chains newer than the last `codified from spec v<n>` stamp and for marked-for-review dependents; regenerate only those groups **+ their dependents**. List the scope and confirm with the user (fresh project vs overhaul sweep vs re-codify subset).
2. Generate token primitives + semantic **`ThemeExtension`** classes + `BuildContext` extensions (spec §4, in order).
3. Wire fonts (per the **typography** decision).
4. **Assemble the app-wide `ThemeData`** (see *ThemeData assembly*) so no stock Material leaks.
5. Generate core widgets from the inventory (§6), category by category — applying the HTML→Flutter conversion table, the MediaQuery policies, and the accessibility-semantics rule to every widget, and reconciling literals (rule 8) before writing each family.
6. Generate the `/gallery` route, rebuild the north-star screen from the new tokens + widgets, and run **Verification** against `design/north_star.html` / `design/system_gallery.html`.
7. On an overhaul: sweep existing screens onto the new tokens/widgets incrementally (theme first, shared widgets second, screens last) — big-bang restyles break everything at once.
8. **Hand back.** Point `/ui` discovery at the new inventory; route any gaps found during codification back to `/design-style` (never patch locally). Ensure the CI **Enforcement** check is in place. **Stamp `codified from spec v<n> on <date>`** into the spec's **Closure (§7)** section **and** into every generated theme file header, and declare the handover: from here the code is canonical and the spec is the decision record — any later code change to a locked value must supersede the matching spec entry (and update `tokens.json`) *in the same change*, or the record silently lies (advisory docs drift; only enforced ones don't).

## Checklist

- [ ] Gate verified: zero UNDECIDED/PROPOSED entries; every SUPERSEDED chain resolved to its final entry
- [ ] `design/tokens.json` present and in parity with spec §4; values **transformed** from it, never re-derived from prose
- [ ] Invariants (§5) each landed as an API constraint or a doc-header rule
- [ ] Every spec §4 group has its code home; primitives private; theme-varying groups are `ThemeExtension` subclasses on `context.*`, static classes only for theme-independent values
- [ ] Dark values codified alongside light for every role (or theme-independence honored per the light/dark strategy decision)
- [ ] App-wide `ThemeData` assembled: `ColorScheme`, `splashFactory`, selection theme, scrollbar + `ScrollBehavior`, `textTheme`, `SystemUiOverlayStyle`, `keyboardAppearance` — no Material leak
- [ ] Fonts: VF bundled once with `fontVariations` per non-default axis (wght/wdth) / static families declare every weight; license allows embedding
- [ ] Every §6 component generated with all decided variants and states; enum/slot APIs, no raw style params
- [ ] Custom controls carry the Semantics role Material gives free (`toggled` / slider+value / `button` / `header` / `liveRegion`) **and** `semanticsIdentifier`
- [ ] Widgets satisfy `/ui` contract (semanticsIdentifier, stateless outer, const, one class per file)
- [ ] Literals reconciled: every §6 value maps to a token, a routed-back new token, or a named sanctioned constant; literal-grep clean
- [ ] Conversion table applied: leading `even`; em-tracking multiplied out; shadow blur via `0.866·B − 0.87` + lists reversed; beziers copied by value; `.withValues(alpha:)`; uppercase + tabular figures inside the role widget; `ClipRRect(antiAliasWithSaveLayer)` for child-reaching radii; gradient angle → begin/end vector; `StrutStyle` where multiline height must match
- [ ] MediaQuery policies wired: textScaler clamped per role; reduced-motion → cross-fade; silent-policy items (haptics/focus/orientation/RTL) routed back, not invented
- [ ] Data-viz palettes → chart token class; map style asset derived from the neutral ramp; map/chart package choice recorded in the spec
- [ ] Signature element codified to its actual form (programmatic → CustomPainter + animation driver reading tokens, not an assumed gradient/asset)
- [ ] Voice & microcopy → copy constants consumed by empty/error/permission widgets
- [ ] Platform surfaces → icon/splash/native config + `SystemUiOverlayStyle` + haptic wrapper
- [ ] `/gallery` route generated: all tokens + every widget × every state + long-text and small-width variants
- [ ] Verification: throwaway-golden vision loop backed by tokens.json assertions; permanent goldens only for atoms with tolerant comparator + real `FontLoader`; on-device side-by-side; 1px borders/shadows re-checked numerically
- [ ] CI **Enforcement** check in place (`Color(0x` / `Colors.` / raw `TextStyle(` / numeric `EdgeInsets` outside token/theme files; token-file diff coincides with `DESIGN_SPEC.md` diff); lints/widgetbook offered
- [ ] Spec stamped `codified from spec v<n> on <date>` in Closure (§7) + generated file headers; code-is-canonical handover declared; gaps routed back to `/design-style`
