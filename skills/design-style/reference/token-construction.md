# Token construction — building the foundation layer right

How each token group gets constructed, what complete looks like (real counts from real systems), naming that survives, and the over-engineering guardrails. All values recorded in the spec must be concrete: hex, px, ms, named curves.

**Architecture (applies to everything below):** two tiers — **primitives** (raw ramps and scales, context-free, never consumed by product code) and **semantic roles** (intent-named, the only layer app code touches, the layer that swaps for dark mode). A third component-token tier (`button.primary.background`) is a known over-engineering trap (real systems have drowned in 500+ button tokens) — skip it; component styling lives in the component widgets themselves. Semantic names describe intent, never value: `textError`, `paddingCard` — a name containing its value (`spacing16`) lies the day the value changes, and value-names (`blue500`) break on rebrand.

## Color

**Construction:** build each hue as a perceptually-even lightness ramp — 10–13 steps (Tailwind 11, Radix 12, Material 3 tones 13, Carbon 10). Use OKLCH or HCT thinking (even lightness steps, no hue drift), not naive HSL math. Tools worth naming to the user: Leonardo (contrast-driven), Huetone.

**Complete inventory:** 1–3 brand hues + ONE neutral family (never mix neutral families) + 4 status hues (success/warning/error/info), each ramped → distilled to **~20–40 semantic roles**:
- surfaces: 3–5 (canvas, surface, raised, overlay — dark mode needs the depth levels; a single background token is a documented retrofit regret)
- text: 5–6 (primary, secondary, tertiary/hint, disabled, inverse/on-primary, error)
- borders: 2–3 (default, divider, focus)
- interactive: primary/accent × (rest, pressed, disabled)
- status × (text, background) each

**The Radix per-step job model** (useful when deriving roles from a ramp): 1 app bg · 2 subtle bg · 3 component rest · 4 hover · 5 selected · 6 subtle border · 7 interactive border · 8 strong border · 9 solid accent · 10 solid hover · 11 low-contrast text · 12 high-contrast text.

**Dark mode:** semantic roles keep their names; only values swap. Rules: base near #121212, never pure black; accents desaturated (vivid hues read neon on dark); elevation expressed as *lighter surfaces*, not shadows; every semantic role gets its dark value at definition time — retrofitting dark onto scattered colors is a rewrite.

**Accessibility floor:** WCAG AA — 4.5:1 body text, 3:1 large text and UI components. Check every text-on-surface pairing as it's locked. (APCA is a useful sanity check for dark mode but is NOT the standard — WCAG 2.2 remains the compliance line.)

**Regret bank:** 226-color palettes; "130 shades of gray"; ten different blue-500s from hardcoding; mixed neutral families; state-token explosions. When in doubt, fewer.

**Gradients (when the signature element or a fixed surface uses one):** a gradient is a token, not an improvisation — record stops (hex + position), angle/direction, and the usage rule ("primary CTAs and the auth backdrop, nowhere else"). One or two gradient tokens is a signature; five is noise. Both light and dark values if the surface themes.

## Data-viz palettes

Construct only when the data-viz rung isn't N/A. Carbon's method:

- **Categorical:** 5–8 hues max, sequenced for neighbor contrast (adjacent series maximally distinct, never adjacent on the wheel), each ≥3:1 against the background (WCAG 1.4.11); colorblind-check mandatory (deuteranopia at minimum, via a simulator). Derived from the brand's temperature but **NEVER** reusing the brand accent or the status hues as category colors.
- **Sequential:** one ramp, even perceptual lightness steps (reuse the OKLCH ramp method above), for magnitude data.
- **Diverging:** two ramps meeting at a neutral midpoint — only for data with a true zero/midpoint.

**Chart chrome tokens ride along:** gridline, axis-label ink, crosshair, tooltip surface. Roles like `chart.series1..n`, `chart.grid`, `chart.axisText`.

**Regret bank:** reusing success-green / error-red as category colors (collides with status semantics); rainbow categorical for ordered data (that's a sequential ramp's job).

## Typography

**Construction:** anchor body at 16 (14–17 native OK) → pick ONE ratio — 1.2–1.25 for product UI (1.125 dense, 1.333+ editorial) → generate ~7 sizes → hand-tune and round line-heights to the 4px grid (pure geometric scales drift off-grid; per-style hand-picked line-heights are the #1 implementation failure).

**Complete inventory: 5–7 composite semantic roles** — each bundling size + line-height + weight + tracking TOGETHER (heading ×3, body ×2, label/caption ×1–2). Material's 15 roles are a menu to trim, not a target. Weights: 2–3 from 400/500/600/700; hierarchy by size first, weight second. Tracking: tighten large display (−0.02em), loosen all-caps labels (+0.05em), body 0. Line-height ~1.5 body / 1.1–1.25 headings.

**Text-scaling policy:** decide NOW which roles honor system font scaling and to what cap (e.g. body/label to 1.3×) and which stay fixed (data-display/hero roles that would break layouts) — recorded per role. This is a token-layer decision, not an implementation detail.

**Regret bank:** style proliferation with no logic chain ("is this 15px or 16px?" debates); untokenized line-height/tracking; five weights when two would do.

## Spacing

**Construction:** base unit from the density rung (8 with 4-halves standard) → a **bounded, non-linear** scale, dense low / sparse high: `0 2 4 8 12 16 24 32 48 64 96` (8–12 steps; Carbon ships 13). No two adjacent steps within ~25%. A scale = base + progression + bounds; without bounds it's just a collection.

**Naming:** numeric primitives; a THIN semantic alias layer only for genuinely recurring intents — gaps (tight/normal/cozy/roomy), paddings (card, page, input, button), section rhythm. T-shirt sizing for spacing is widely regretted (runs out of slots — its own inventor publicly recanted it). Our stack's existing shape (gap*/padding*/section* roles over numeric primitives) matches the consensus.

**Also lock here:** page margins (16 phone / 20–24 tablet), tap-target floor (44pt/48dp), hairline (1).

## Shape & borders

**Radius:** own scale, not derived from spacing — ~6 steps + none + full covers everything (you'll actively use ~3: controls, cards, pill). Semantic roles per surface class: control/field, chip, card (sm/md/lg), sheet, pill. Record the **nested-radius law: inner = outer − parent padding** — never equal on parent and child.

**Borders:** two widths — 1 default/divider, 2 focus/emphasis. Prefer borders over shadows for separation in dense layouts and always in dark mode.

## Elevation

**4–6 role-named levels** (sunken / default / raised / overlay — role names scale better than numbered dp ladders). Light mode: layered, background-tinted shadows (offsets doubling 1/2/4/8/16, opacity dropping as elevation rises, never pure black). Dark mode: the SAME roles map to surface lightness steps (+5–8% luminance per level) — shadows are invisible on dark. If overlays stack, pair the roles with a z-index ladder in steps of 100 (dropdown < sticky < modal < popover < toast).

## Icon sizes

From the iconography rung: size scale **16 / 20 / 24 / 32 / 40** with 24 the workhorse, plus chevron sizes if the set's chevrons run smaller. Icon ≠ touch target: small icons pad out to the 44/48 floor. Scale only at scale-multiples — arbitrary sizes blur stroke alignment.

## Motion

**Complete inventory is small: ~5 durations + 3–4 easings ≈ 9 tokens.** Durations 100–400ms (under 100 reads instant, over 500 drags); enters slightly longer than exits; duration scales with travel distance. Easing rules: **enter = decelerate (ease-out), exit = accelerate (ease-in), within-screen = ease-in-out, linear only for spinners/opacity**. Built-in curves are weak — use pronounced beziers (Material's standard `cubic-bezier(0.2, 0, 0, 1)` is a good base). The personality rung decides whether a second "expressive" set exists at all (Carbon's productive/expressive split is the model — most apps need only productive).

**Rules riding along:** honor reduced-motion by *replacing* movement with cross-fades, not deleting feedback; never animate frequent/repeated actions conspicuously; animate transforms and opacity only.

## Budget sanity (closure gate for Phase 4)

| Group | Sane range |
|---|---|
| Color semantic roles | 20–40 |
| Type roles | 5–7 |
| Spacing steps | 8–12 (+ ~8 semantic aliases) |
| Radius roles | 4–7 |
| Elevation levels | 4–6 |
| Icon sizes | 4–6 |
| Motion tokens | ~9 |
| Data-viz palette | categorical ≤8 + 1–2 ramps + ~4 chrome roles |

Totals far above these ranges mean over-decomposition (decision fatigue, adoption failure — devs route around systems they can't navigate); far below means literals will creep in to fill gaps. Tokens define values, not behavior — usage rules live in the spec prose and later in `/ui`.

On Phase-4 close, the locked groups are emitted as `design/tokens.json` (W3C DTCG shape: `$value`/`$type`, aliases for semantic→primitive references) — the machine contract `/design-codify` transforms. The spec keeps the reasoning; `tokens.json` keeps the truth; they update together.
