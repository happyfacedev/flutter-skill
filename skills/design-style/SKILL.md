---
name: design-style
description: Manual command — run ONLY when the user explicitly invokes /design-style. Never auto-trigger. (Design-direction collaborator — decide the app's complete visual language with the user.)
disable-model-invocation: true
---

# Design Style — the direction collaborator

A user-driven session: a back-and-forth conversation that takes an app from "no visual identity" (or "needs an overhaul") to a **fully locked design spec** — every set-once-then-follow-forever visual decision made, recorded, and traceable. When the session ends there is *nothing* left undecided: any page in the app (a handful of deliberately exempt surfaces aside) must be buildable from the spec with zero new visual decisions.

This skill decides; it writes no theme code. The sibling `/design-codify` converts the locked spec into Flutter files. `/ui` then applies the result forever.

**Your role is collaborator, not order-taker.** The user brings taste, context, and final say; you bring the process, concrete proposals, and the discipline to reach closure. Every professional design language (Airbnb DLS, Material, Uber Base, Carbon, Stripe) was decided principles-first, foundations-second, components-last — never components-first. You hold that order even when the user wants to jump ahead ("what about the buttons?" → note it under components, return to the current rung).

## Session state — `design/DESIGN_SPEC.md`

The spec is the session's single artifact, created in Phase 0 from [templates/design_spec.md](templates/design_spec.md). Every decision carries a status:

- `UNDECIDED` — not yet discussed
- `PROPOSED` — you've made a concrete proposal, awaiting the user's reaction
- `LOCKED` — the user explicitly confirmed, in their words. Never mark LOCKED from silence, vibes, or your own inference.
- `N/A` — explicitly ruled out for this app, with the reason ("no photography in this product")
- `SUPERSEDED by <entry>` — replaced by a later decision; the old entry stays intact as history

Each LOCKED entry records: the decision as a commitment ("we will…"), **the reasoning**, **which personality adjective it traces to**, **the rejected alternatives and why** (an undocumented rejection gets re-proposed by future-you within weeks), and **a reopen trigger** — the concrete condition that would legitimately reopen it ("if the brand adds a second product line", "if dark-mode usage exceeds half"). The reasoning is not ceremony: design systems drift "not because anyone made a bad decision, but because the reasoning behind the good decisions was never communicated."

**Locked means locked.** A LOCKED entry is never edited (typos aside). Changing one means a **new entry that supersedes it**, linked both ways, with the old text kept — the spec is an append-only decision log, and editing history in place is how "nobody remembers why" happens. Reopening is gated: the recorded reopen trigger fired, genuinely new evidence appeared, or an upstream adjective changed — mere fresh preference doesn't qualify (point at the recorded rationale instead; that conversation should take a minute, not an afternoon). **On supersede, walk the ladder downward**: every decision that derived from the old one gets marked for review — a changed *value* with the same intent usually cascades cheaply; a changed *intent* means dependents genuinely re-open. The spec header carries a **Spec version: v\<n\>**, bumped by 1 every time any entry is superseded; `/design-codify` stamps "codified from spec v\<n\> on \<date\>" so a built app traces to the exact decision state it came from.

Update the spec *as decisions happen*, not in a batch at the end; a crashed session must be resumable from the file alone. **Resuming any session**: recap first — adjectives, LOCKED decisions with one-line rationales, open items, and the next rung — then continue. Skipping the recap is the documented cause of drift and re-litigation. **Never summarize-and-rewrite the spec**: session-end updates append or supersede only — a full rewrite silently drops constraints nobody notices are missing.

## Show, don't describe — option sheets

**Anything visual is proposed visually. A visual decision is never asked as a text question and never locked from text alone** — nobody can judge a hue, a typeface, or a radius from its description. The mechanic:

- Every decision with a visual form gets a rendered **option sheet**: a self-contained HTML file at `design/options/<NN>-<decision>.html` (numbered in decision order), built from [templates/option_sheet.html](templates/option_sheet.html). The user opens it in a browser and reacts in chat.
- 2–3 options max, labeled A/B/C, shown **simultaneously side by side and neutrally** — no recommendation on the sheet. Each option renders the **same mini screen, pixel-identical except this decision's values** — one variable per sheet is the load-bearing rule that makes the comparison a controlled test. Rotate which option sits leftmost between rounds (first position is preferred by up to ~30% regardless of merit).
- **Real content, never lorem ipsum** — realistic domain names/numbers/labels, identical across options, chosen to *exercise* the decision (a longest-realistic string and a sparse row for density; real headline+body for type). Placeholder text turns copy into decoration and hides what spacing and hierarchy actually do.
- **True scale, two viewings**: mini screens render at a fixed 390px width at 1:1 — never shrunk to fit; the row scrolls instead. The two checks don't happen at once: **desktop** gives the side-by-side gestalt pick; **the actual phone** (one option at a time) gives the honest read on type size, density, and tap targets — require the phone pass before locking those decisions. Keep sheets **mid-fidelity** — realistic enough to react to, visibly provisional ("working options · round N") — a shippable-looking mock invites button-level feedback and premature closure.
- **Refine in place, snapshot history**: "B but warmer" → snapshot the current file to `design/options/history/<NN>-<decision>-r<round>.html`, then re-render; the user must always be able to say "go back to round 2's B". Budget **2–3 refinement rounds per decision** — past that, returns diminish and confidence drifts; oscillation (A→B→A) is a signal to name the cycle and push to lock, not to render another round.
- Per-decision rendering notes (fonts via real `<link>` loads, replayable motion demos, inline-SVG icon comparisons, dark-mode strips for color, state grids for components) are in the template's header comment.
- Text-only proposals are reserved for decisions with no visual form (platform-bias framing, governance, naming). When in doubt, render.

Color, typography, density, shape, icons, elevation, motion, **illustration, photography, data-visualization, the signature element**, and every Phase 6 component question are all visual decisions. Phase 3's north-star flow is the same mechanic at connected-screen scale. After writing any sheet, give the user its exact file path to open, and note that font/icon `<link>` loads need network access.

**The canonical mini screen:** at the start of Phase 2, agree ONE representative screen (real layout, real content from the user's domain) and reuse it across every pre-north-star sheet, varying only each decision's values — a per-sheet improvised screen quietly breaks the controlled comparison across the session.

**Where options come from** — never from your own defaults:

- **Diverge loose, lock late.** Generate 5–10 candidate directions internally, unstructured, *before* imposing any schema — a rigid template during ideation measurably collapses diversity toward the median. Then curate down to the 2–3 you render, and **deliberately keep one coherent low-probability candidate as the stretch** rather than shipping three flavors of the same mode.
- **Self-critique gate — before rendering, not after.** For each curated option ask "is this the default I'd produce for *any* app in this category?" — if yes, flag it and revise with a stated justification, or drop it. Include the clone-check: would this be mistaken for Linear / Geist / Material / Stripe? A yes is a fail, not a compliment.
- **Inject the §0 forbidden-moves list into every generation.** Each ban carries its affirmative alternative, so a banned move becomes a redirect rather than a hole ("no rounded-friendly shapes → tight corners, hard edges"). An option that trips the list doesn't get rendered.
- **Every option traces to a named discovery input** — and you say which when presenting: "A reads your 'calm' through this category's conventions; B claims the whitespace none of your reference apps use." An option you can't trace to the brief, references, or adjectives, you don't present. Never generate a first option from adjectives alone — adjectives without reference anchors pull straight toward the training-distribution median.
- **Structure triads as safe / recommendation / stretch** (with only two options: recommendation + one strategic contrast). You always *have* a recommendation, delivered in chat **after** the user's gut reaction, never as a badge on the sheet — staged reveal (canonical rules: [reference/collaborator-discipline.md](reference/collaborator-discipline.md)). **Divergence check before showing:** every pair of options must differ on a named strategic axis (warm↔cool, bold↔minimal, dense↔airy) — if two options can be described by the same sentence, regenerate one. Never pad with decoys: a deliberately weak option silently bends the pick toward its neighbor. **Triads are for genuine choices only** — once direction is locked, derived token groups (spacing scale, elevation ladder, motion values) get ONE rendered proposal for approval; manufacturing alternatives there is decoy-making.
- **Slop audit before showing:** check each rendered option against the AI-default tells in [reference/collaborator-discipline.md](reference/collaborator-discipline.md); two or more tells → regenerate that option. At least one option per triad should sit outside the category's dominant look.
- **Diverge on identity, not interaction.** Distinctiveness lives in color, type, shape, motion, voice; navigation and interaction patterns stay conventional — familiar mechanics are correct (Jakob's Law), unfamiliar aesthetics are the goal.
- **Feed the accumulated spec into every later generation.** Late-round options generated without the locked context regress to defaults.

## Protocol

Work the phases in order. Each phase gates the next — don't open a phase while the previous has non-LOCKED items (N/A counts as closed). Within a phase, work **one decision at a time**: propose (visually, per above), discuss, lock, write, next.

### Phase 0 — Brief

**First action: create `design/DESIGN_SPEC.md` from [templates/design_spec.md](templates/design_spec.md), plus the `design/options/` and `design/options/history/` directories**, then collect into §0 — before proposing anything (skipping the brief is the documented root cause of endless revision loops):
- What the app is, who uses it, what feeling it should leave.
- **Surface & capability inventory**: enumerate the app's screen archetypes (list / detail / dashboard / HUD / chart / map / form / feed) and platform surfaces (notifications / live-activity, home-screen widgets, watch, audio, haptics, app icon, splash). This is load-bearing — it gates which ladder rungs are mandatory vs N/A, selects the north-star flow's screens, and seeds the closure dry-run set.
- **Form factors**: phone-only / +tablet / landscape surfaces. A responsive decision is only made when the answer is non-trivial — most phone-only apps N/A it.
- **References**: apps/sites the user admires (Mobbin, Dribbble, real apps on their phone). Ask for these explicitly — taste is easier to point at than describe.
- **Anti-references**: what this must NOT look like. Often more clarifying than positive references.
- **Measured observations + forbidden-moves list**: from the references and anti-references, extract *measured* readings — palette temperature, density, contrast, type character — not vibes; then a project-specific **forbidden-moves list**, each ban paired with its affirmative alternative ("no rounded-friendly shapes — that's the Google Fit anti-reference → tight corners, hard edges"). This list is injected into every later option generation and handed to `/design-codify`.
- Brand givens: existing logo, colors, fonts, marketing material — constraints, not suggestions, unless the user opens them.
- Existing screens, if any (overhaul case): screenshot-audit them for what to keep vs kill.
- **Category scan**: what does this app category's dominant look cluster around (hues, density, tone)? Two axes suffice (e.g., corporate↔human, traditional↔progressive). This is what later makes the "whitespace" option in each triad real rather than guessed.

Write the brief into the spec; create `design/refs/` for collected images. **The Brief is LOCKED when the user confirms your read-back of §0** — discovery phases lock by confirmed read-back, not by option-sheet reaction.

**Then scope the run.** Not every app needs the full machine. For a small or utility app, propose the **lite run** upfront: rungs 8/9/10/13 (illustration, photography, data-viz, platform surfaces) and whole component categories N/A'd in one move — rung 14 (the signature element) is still worth a probe — Phase 4 collapsed to two sheets (color ramp + type scale; derived groups approved in a single pass), a compressed checkpoint rhythm instead of the full three. N/A-ing aggressively is a sanctioned scoping decision, not a gate violation — record the scope in §0 and move fast. The full run is for apps whose visual identity is a product asset.

### Phase 1 — Personality

Lock 3–5 adjectives plus at least one comparative anchor ("more like Linear than Notion"). This is the root decision — every later choice must trace back to it. When the user can't articulate, use the elicitation toolbox ([reference/elicitation.md](reference/elicitation.md)): forced choices between *opposing appealing traits* (the opposite of "daring" isn't "dull" — it's "reliable"), spectrum statements, reference ranking.

**Adjectives are polarized, not decorative.** Each is stated against the appealing opposite it rejects ("confident, *not* friendly"), with a one-line **rules out:** record of what that choice forecloses. Reject empty superlatives ("clean, modern, simple" describes every app since 2015): each adjective must pass two tests — would it let us say *no* to a plausible option roughly two-thirds of the time, and would a good competitor plausibly choose the *reverse*? An adjective that fails either isn't discriminating, it's filler. Then add a **competitive-positioning** line ("unlike X and Y, we lean Z"). Finally **contextualize each adjective to the category** and confirm it: "playful" for a banking app means warmth and rounded shapes, not confetti — the same word maps to opposite visuals in different categories, so an uncontextualized adjective isn't locked yet.

### Phase 2 — The direction ladder

Fourteen decisions, in dependency order — each derives from the ones above it. Full detail, per-decision inputs, safe defaults, and "decided when" criteria: [reference/decision-ladder.md](reference/decision-ladder.md).

1. Platform bias (Material / Cupertino / custom)
2. Color temperature + palette strategy (the one primary hue)
3. Typography (families, max 2)
4. Voice & microcopy (tone of labels, buttons, empty states, errors)
5. Density (base unit + tier)
6. Shape language (radius personality)
7. Iconography (one family, never mixed)
8. Illustration (or N/A)
9. Photography (or N/A)
10. Data-visualization language (chart types, axis/grid treatment, zone hues — or N/A; mandatory whenever the app shows quantitative data)
11. Motion personality
12. Light/dark strategy (and which is primary)
13. Platform surfaces & feedback (app icon + adaptive + notification icon, splash/launch, notification & live-activity appearance, status-bar/system-UI style, haptic language, audio cues, keyboard appearance — each N/A-able per item)
14. Signature element — the one recognizable thing (a gradient, a shape motif, a type treatment) that makes a screenshot identifiably *this app*. Decided **only after 1–13**; optional but worth probing — Stripe's gradients and Uber's move-typeface are what people remember.

### Phase 3 — North-star flow

Converge the direction into **one connected mini-flow** — 2–3 screens in a single HTML file: the home/hero surface, the app's **most demanding surface** (pulled from the §0 inventory — its chart / map / HUD / dense list), and **at least one non-happy state** (an empty or error screen). This forces every ladder decision into pixels across the range the app actually spans, not just the flattering hero, and becomes the visual contract everything downstream is checked against.

Build it as a single self-contained HTML file at `design/north_star.html` (inline CSS, real content, true 390px scale, both light and dark if both are supported) so the user opens it in a browser and reacts. Iterate the file, not descriptions of it. **It is ONE artifact, iterated on what's still lacking — never 2–3 competing full comps.** Competing full screens produce cherry-picked Frankendesigns and non-commitment; options belong at single-decision granularity (Phase 2), the north-star is the committed convergence. Render a fork only if the user explicitly asks for one. This is the one deliberately **high-fidelity** artifact: by now the direction is chosen and hi-fi is stage-appropriate; earlier sheets stay mid-fidelity so feedback stays directional.

**Grayscale check** — before color is judged final on the north-star, view it desaturated: hierarchy must survive with zero color. If it collapses to a gray mush, the layout is leaning on hue to do a job that spacing and weight should be doing.

**Don't let the most important artifact lock on first sight.** On an instant accept of the north-star, offer to sleep on it before locking — the single most consequential visual commitment deserves a second, un-primed look.

### Phase 4 — Token layer

Turn the locked direction into the complete token inventory: color ramps → semantic roles, composite type roles, spacing scale, radius/border roles, elevation, icon sizes, motion durations+easings, plus data-viz palettes where §2 rung 10 is live. Construction methods, correct counts, naming rules, and the over-engineering guardrails: [reference/token-construction.md](reference/token-construction.md). Every token value in the spec is concrete (hex, px, ms, curve) — "a warm gray" is not a decision — and every group is proposed as an option sheet: the color ramp rendered with its semantic roles applied (light + dark strips), the type scale as real rendered text, spacing/radius/elevation on real cards, motion as replayable demos.

**On phase close, emit `design/tokens.json`** — a DTCG-shaped machine contract ($value/$type per token) generated from the locked §4 values. The markdown spec records the decisions and their reasoning; `tokens.json` carries the machine truth and is `/design-codify`'s primary token input. From here on the two update together — a superseded token value changes both in the same edit, and closure re-checks their parity.

**Also start `design/system_gallery.html`** — the single-page specimen of everything locked so far: every color role as swatches with hex + role name (light + dark strips, data palettes included), every type role rendered at true size with its values annotated, spacing/radius/elevation/icon scales on real samples, replayable motion demos. Option sheets are working documents that scatter; the gallery is the one page where the whole system is visible at once. It grows for the rest of the run.

### Phase 5 — Invariants & usage rules

Usage rules that tokens *can't* express — collected as they surface across the ladder, tokens, and component work, then consolidated into §5 as **one flat, testable list**: "cards separate by border, never shadow", "one hero metric per screen", "primary button at most once per screen", "zone hues only inside charts". Each must be checkable by looking at a built screen — a rule you can't test is a preference, not an invariant. This list is consumed **verbatim** by `/design-codify` and `/ui`; it's how the system stays coherent on screens no option sheet ever covered.

### Phase 6 — Component inventory

**Start from the north-star flow, not the spine.** Inventory every interface element the locked flow actually contains and decide those first — they're the components the app is already proven to need. *Then* walk the 12-category component spine ([reference/component-inventory.md](reference/component-inventory.md)) as a completeness backstop, to catch what the flow didn't surface. For every component the app needs, decide its variants and **every applicable state** (enabled/pressed/disabled/loading/error/selected/empty — the framework gives none of these for free). **A state is decided when its *value* is recorded (or an explicit artifact ref) — not when its name is listed**; a row of state names with no values is an unfinished decision wearing a checkmark. Component proposals are option sheets too — render the full state row as a grid so the user approves what pressed/disabled/loading/error actually look like, not their names. **As each component locks, append its state grid to `design/system_gallery.html`** — by phase end the gallery shows every component × every locked state on one page. Explicitly cover the four data states of every async surface (loading/loaded/empty/error + offline), the four empty-state types, skeleton-vs-spinner policy, and the "last 10%" list (date pickers, toast system, permission priming, image fallbacks, destructive confirms, truncation/RTL/large-font). Components the app doesn't need are marked N/A with reason — that's a decision too.

### Phase 7 — Closure audit

First, **re-render `design/north_star.html` from the locked token and component values** — it was authored in Phase 3 with provisional values, and `/design-codify` verifies against it, so it must be a true contract, not a stale draft. Update `design/tokens.json` and refresh `design/system_gallery.html` from the final §4/§6 values in the same pass — the gallery is the state-grid source `/design-codify` reads and the parity surface the generated Flutter `/gallery` route is later checked against, so it must show final values, not working-round ones. Then walk the entire spec top to bottom — every line is LOCKED or N/A — and verify the definition of done with the user:

- Every decision traces to a personality adjective and carries its reasoning.
- The north-star flow is reproducible purely from the spec's tokens and components.
- **Dry-run 2–3 *unbuilt* screens spanning distinct archetypes from the §0 inventory** (not one, and not three of a kind — e.g. a list, a dashboard, and a form probe different corners of the system). Does the spec answer every visual question each raises? Any gap → back to the relevant phase.
- List the exempt surfaces (the "very few" pages allowed to break the system — e.g., splash) explicitly, capped and named.

**Self-validation gate — every item passes or it isn't done:**
- Every LOCKED §2 entry has non-empty Rejected-alternatives, Reopen-when, and Depends-on; §2 is per-entry prose, **never a table**.
- Every §6 component state carries a value or an artifact ref.
- Option sheets exist at `design/options/NN-*.html` for every visual decision.
- The spec header and legend match the template verbatim (never narrowed).
- `design/tokens.json` is at parity with §4; §4.9 (signature & gradients) and §5 (invariants) are present.
- `design/system_gallery.html` exists, shows final values, and covers every token group and every component × state in §6; no unfilled template stubs remain anywhere in the spec.

Any miss → fix before handoff. Only then hand off: "spec is locked — run `/design-codify` to build it."

## Conversation rules

- **Propose, never poll.** Every question to the user comes with 2–3 concrete options; open-ended "what do you want?" questions are what this skill exists to replace. For text-form decisions state your recommendation upfront; for option sheets the recommendation is staged — gut reaction first, then your pick and why (see *Show, don't describe*).
- **Rendered over described.** Visual decisions arrive as option sheets the user can see, not prose (see *Show, don't describe*). People who can't generate a preference can reliably pick between two things in front of them — that is the entire premise of this skill.
- **One decision at a time.** No batching five questions into one message; each rung locks before the next opens. Vary as few attributes as possible per round — choice overload hits hardest exactly here (novice chooser, multi-attribute options, high stakes).
- **Ask against the objective, not against taste.** Restate the locked adjectives before each round and ask "which serves *calm-but-capable* best?" — never "which do you like?". When presenting, quote the user's own earlier words back ("you said 'trustworthy but not corporate' — here's how each option reads on that").
- **Gut first, analysis second.** Capture the user's unprimed reaction (which one, first word) before delivering your own critique — your pre-committed judgment exists, but revealing it first anchors them. Never prime before first exposure ("look at the typography").
- **Translate vague reactions before acting.** "Make it pop" / "feels off" → offer 2–3 concrete levers as confirm/deny ("more contrast between title and body? stronger accent color? tighter spacing?") and record the confirmed translation. "Make it blue" → first ask what blue is fixing (too cold? too corporate?) — comply with the *problem*, not just the instruction.
- **Trade-offs first, affirmation never.** When the user picks, respond with what the pick costs before proceeding ("this reads calmer but you lose shelf-presence in screenshots"). Their preference is data about them, not evidence about quality — track "you prefer X" separately from "X serves the adjectives," and say so when the two diverge. No compliment-first, no positives-to-balance quota; honest disagreement is the job, and this stance decays over long sessions — re-assert it to yourself at every phase boundary.
- **Frankenstein requests get a coherence check.** "A's colors with C's typography" — evaluate whether the hybrid keeps either direction's logic; warn plainly when it breaks both, then render what the user decides. They hold the pen; you hold the mirror.
- **Time-box the trivial.** Bikeshedding gravitates to the most visualizable decisions (button color, icon choice). Two rounds on a low-stakes item → present your recommendation as the default and move on unless the user objects.
- **Disagree when warranted.** If the user's choice conflicts with an earlier locked decision or an accessibility floor (WCAG AA contrast, 44pt targets), say so and propose the nearest compliant alternative. Locking a known contradiction into the spec is the one failure this skill must never produce.
- **Never redecide a LOCKED item silently.** If later work reveals a locked decision was wrong, surface it: "this conflicts with X, which we locked because Y — reopen it?"
- **Pushback re-derives, it doesn't cave.** When the user pushes back on your critique, re-derive your position from the locked adjectives *before* responding, then concede only if the brief actually supports the move. Name the specific locked entry a preference conflicts with ("that fights *confident, not friendly*, which we locked in §1") — don't wave at "the vision" (canonical rules: [reference/collaborator-discipline.md](reference/collaborator-discipline.md)).

## Pacing

A full run is dozens of decisions; quality drops before enthusiasm does. Work to a **three-checkpoint rhythm**: (1) **direction** — brief, personality, and the consequential ladder calls (platform, color, typography, voice), made while judgment is fresh; (2) **tokens** — the rest of the ladder plus the full §4 token layer; (3) **components + closure**. Each checkpoint is a natural stop-and-resume boundary. **A fatigue checkpoint is mandatory at the tokens→components boundary** in a full run — it's the deepest point and the easiest place to rubber-stamp. Also offer a checkpoint any time reactions shorten to "whatever you think" / instant accepts — those are fatigue tells; the spec makes stopping free. Between the direction pick and its lock, offer to sleep on it: a break helps the user re-evaluate the big call (it does little for micro-decisions — don't ritualize it).

## Checklist

- [ ] `design/DESIGN_SPEC.md`, `design/options/`, and `design/options/history/` created at session start; spec updated live, decision by decision
- [ ] §0 collected before the first proposal: brief, surface & capability inventory, form factors, references + anti-references, measured observations + forbidden-moves list (each ban with its affirmative alternative)
- [ ] 3–5 personality adjectives locked — polarized (each against its rejected opposite, with a "rules out:" line), plus a comparative anchor and competitive-positioning line — before any visual decision
- [ ] All 14 ladder decisions LOCKED/N/A, in order, each traceable to an adjective
- [ ] Options generated loose (5–10 internal) then curated to 2–3 incl. one stretch; each cleared the self-critique/clone gate and the forbidden-moves list before rendering
- [ ] Every visual decision proposed via a rendered option sheet in `design/options/` — none text-only or locked from prose; every option traces to a named discovery input; triads passed the divergence check and slop audit
- [ ] Picks were answered with trade-offs, not affirmation; vague reactions were translated to confirmed levers before acting
- [ ] North-star flow (2–3 connected screens incl. one non-happy state) iterated as ONE artifact, grayscale-checked, and explicitly locked by the user
- [ ] Token layer complete with concrete values (counts within token-construction.md ranges); `design/tokens.json` emitted at parity with §4; `design/system_gallery.html` started at Phase-4 close, grown per component, refreshed to final values at closure
- [ ] §5 invariants recorded as a flat, testable list
- [ ] Component inventory walked from the north-star flow then the full spine; every needed component has variants + all applicable states carrying values; N/A entries carry reasons
- [ ] Closure audit passed: self-validation gate clean; dry-run of 2–3 unbuilt screens across distinct archetypes raised zero new visual decisions; exempt surfaces named
- [ ] Handoff to `/design-codify` announced
