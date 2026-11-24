# Design Spec — <App Name>

**Spec version:** v1

> These header lines are verbatim boilerplate — never rewrite or narrow them.
> Session artifact of `/design-style`. Statuses: `UNDECIDED` · `PROPOSED` · `LOCKED` · `N/A (reason)` · `SUPERSEDED by <entry>`.
> LOCKED entries are append-only: never edited (typos aside) — changes create a superseding entry linked both ways, and bump **Spec version** by 1.
> Consumed by `/design-codify`, which refuses to run while anything is UNDECIDED or PROPOSED, reads `design/tokens.json` as the machine token contract, and stamps "codified from spec v<n> on <date>".
> **After codification the code is canonical**; this file remains the decision record — if code later changes a locked value, supersede the entry here in the same change.

## Resume point

> Kept live through completion — updated every session, including the last.

- **Next up:** <next rung / phase>
- **Locked so far:** <count> · **Open:** <count>
- Last session: <date, one line on where it ended>

## 0 · Brief — UNDECIDED

- What the app is / who it serves:
- Feeling it should leave:
- **Surface & capability inventory** (screen archetypes: list / detail / dashboard / HUD / chart / map / form / feed · platform surfaces: notifications/live-activity, widgets, watch, audio, haptics, app icon, splash) — gates mandatory-vs-N/A rungs, picks the north-star screens, seeds the closure dry-run set:
- **Form factors** (phone-only / +tablet / landscape surfaces — a responsive decision only if non-trivial):
- References (ranked, see `design/refs/`):
- Anti-references:
- **Measured observations** (read off the refs/anti-refs, not vibes — palette temperature, density, contrast, type character):
- **Forbidden moves** (each ban + its affirmative alternative — e.g. "no rounded-friendly shapes → tight corners, hard edges"; injected into every option generation, handed to `/design-codify`):
- Brand givens (logo, colors, fonts):
- Category scan (dominant look, whitespace):
- **Run scope** (full / lite — what's N/A'd upfront):
- Existing screens audit (overhaul only):

## 1 · Personality — UNDECIDED

- Adjectives (3–5) — one polarized line each: `<adjective>, not <rejected appealing opposite> — rules out: <what it forecloses>` (each contextualized to the category):
- Comparative anchors ("more like X than Y"):
- Competitive positioning ("unlike X and Y, we lean Z"):
- Reasoning:

## 2 · Direction ladder

> One entry per decision, in dependency order. Fill every field on LOCK — the rejected-alternatives and reopen-trigger fields are what stop re-litigation later.
> **One entry per decision — NEVER collapse this section into a table.** Rejected-alternatives / Reopen-when / Depends-on do not survive a table row; a table here is a closure-audit failure.

### 2.<n> <Decision name> — UNDECIDED

- **We will:**
- **Traces to (adjective):**
- **Reasoning:**
- **Rejected alternatives (and why):**
- **Reopen when:**
- **Depends on:** <upstream entries this derived from>

*(Repeat for: 1 Platform bias · 2 Color temperature + palette strategy · 3 Typography · 4 Voice & microcopy · 5 Density · 6 Shape language · 7 Iconography · 8 Illustration · 9 Photography · 10 Data-visualization language · 11 Motion personality · 12 Light/dark strategy · 13 Platform surfaces & feedback · 14 Signature element)*

## 3 · North-star flow — UNDECIDED

- Artifact: `design/north_star.html` (ONE file, 2–3 connected screens — never competing full comps)
- Screens (home/hero · most-demanding surface from §0 · at least one non-happy state):
- Non-happy state shown (empty / error — name it):
- Grayscale check (hierarchy survives fully desaturated — date + outcome):
- Locked on (date + user's words):

## 4 · Token layer

> Same entry discipline as §2 where a group involved a real choice; concrete values always (hex, px, ms, curves).
> **tokens.json emitted / updated:** <date> — DTCG-shaped ($value/$type), parity with this section checked.

### 4.1 Color — UNDECIDED
- Primitives (ramps, concrete hex):
- Semantic roles (light + dark values per role):
- Contrast checks (WCAG AA pass table):

### 4.2 Typography — UNDECIDED
- Families / weights / variable:
- Scale (base, ratio, sizes):
- Roles (size + line-height + weight + tracking each):

### 4.3 Spacing — UNDECIDED
- Base unit / steps:
- Semantic aliases (gaps, paddings, sections):
- Page margins / tap-target floor / hairline:

### 4.4 Shape & borders — UNDECIDED
- Radius roles:
- Border widths:
- Nested-radius rule noted: inner = outer − parent padding

### 4.5 Elevation — UNDECIDED
- Levels (roles) + light shadow values + dark surface mapping:

### 4.6 Icon sizes — UNDECIDED
- Scale + workhorse + touch-target padding rule:

### 4.7 Motion — UNDECIDED
- Durations / easings / usage rules / reduced-motion policy:

### 4.8 Data-viz palettes — UNDECIDED (or N/A — no quantitative data)
- Categorical / sequential / diverging ramps (concrete hex; colorblind-safe check):
- Zone hues (positive / warning / critical) + axis / grid / label treatment:

### 4.9 Signature & gradients — UNDECIDED (or N/A with reason — section always present)
- Gradient tokens (stops hex+position, angle, light/dark values):
- Signature usage rule ("appears on X, never on Y"):
- Illustration / photography assets (style refs in `design/refs/`, container + fallback treatment):

## 5 · Invariants & usage rules — UNDECIDED

> Usage rules tokens can't express — collected as they surface across §2–§6, consolidated here as one flat, testable list (each item checkable by looking at a built screen). Consumed **verbatim** by `/design-codify` and `/ui`.

1.
2.
3.

*(e.g. "cards separate by border, never shadow" · "one hero metric per screen" · "primary button at most once per screen" · "zone hues only inside charts")*

## 6 · Component inventory

> Start from the north-star flow's elements, then walk the full spine as a backstop. One row per component the app needs; contentious calls get a §2-style entry under the table. A state is decided when its **value** (or an explicit artifact ref) is recorded — not when its name is listed. Unneeded components: N/A + reason.

| Component | Status | Variants | States → values | Notes |
|-----------|--------|----------|-----------------|-------|
| Button | UNDECIDED | | | |
| Icon button | UNDECIDED | | | |
| Text field | UNDECIDED | | | |
| … walk the full spine in reference/component-inventory.md … | | | | |

### Data-state policy — UNDECIDED
- Skeleton vs spinner rule:
- Empty-state types (first-use / cleared / no-results / error):
- Offline treatment:

### Last-10% walk — UNDECIDED
- Date/time pickers · toast system · permission priming · image fallbacks · truncation · RTL/large-font · destructive confirm:

## 7 · Closure

- Exempt surfaces (named, capped):
- Dry-run screens + outcomes (2–3, spanning distinct §0 archetypes):
- Self-validation gate (all pass — §2 prose not table · every §6 state valued · option sheets present · header verbatim · tokens.json parity with §4 · §4.9 + §5 present · system_gallery.html at final values covering all token groups + all §6 states · no unfilled template stubs):
- System gallery: `design/system_gallery.html` (refreshed to final values on <date>):
- Locked by (user's words, date):
- Codified from spec v<n> on <date> (by `/design-codify`):

## Working notes

> Session-scoped scratch: pre-commitment rubric scores per option sheet (scored against adjectives BEFORE the user reacts), confirmed vocabulary translations ("pop" = title/body contrast for this user), fatigue observations, sheet round counters. Not decisions — kept for honesty and cross-session continuity.

| Sheet | Round | Options scored (adjective rubric, pre-reaction) | User's gut | Outcome |
|-------|-------|--------------------------------------------------|-----------|---------|
| | | | | |
