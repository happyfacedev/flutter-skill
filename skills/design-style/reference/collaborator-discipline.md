# Collaborator discipline — the two failure modes that compound

An AI design collaborator fails in two measured ways that reinforce each other: it proposes the **training-distribution median** (the "AI look"), and it **validates whatever the user accepts** (sycophancy — models measurably inflate praise for options the user says they like, and agreement drift worsens over long conversations). The structural fix for both is the same: externalized, pre-committed criteria — the locked adjectives, the reference set, the banned-defaults list, and a per-option rubric — that both parties are judged against. This file is that criteria kit.

## The slop-tell checklist (audit every option before showing)

The "AI look" is a documented, quantified fingerprint. Check each rendered option; **two or more tells → regenerate that option** before the user ever sees it:

- Inter / Roboto / default system font presented as a "choice"
- Purple/indigo gradient (especially on white) — the statistical center of scraped "modern UI"
- Gradient text on hero headlines
- Glassmorphism cards / frosted overlays as the default surface
- Emoji used as icons
- Centered hero + three rounded icon-cards row
- Colored left-border cards
- Neon glow accents
- Untinted gray-on-white with default Tailwind-ish shadows everywhere

**Second-order convergence is real:** ban Inter and models converge on the *next* default (the Space Grotesk effect). The checklist is necessary but not sufficient — the positive defense is grounding every option in the user's references, not just avoiding a blacklist. And don't over-ban: a wall of negative constraints produces a different kind of boring. Add bans for observed problems, not hypothetically.

**The clone-check** (run alongside the checklist): would a stranger mistake this for Linear / Geist / Material / Stripe? Distinctive-system cloning reads as "made with X", not "this is your brand" — the checklist catches generic slop, the clone-check catches borrowed identity.

**The project forbidden-moves list:** at brief time, extract from the references/anti-references a bespoke ban list — each ban paired with its affirmative alternative (negation-only constraints are a documented dead end). Inject it into every generation alongside this global checklist. The global list is the floor; the project list is the real fence.

Sameness is only wrong where identity lives. Familiar navigation, familiar form patterns, familiar gestures are *correct* (Jakob's Law) — distinctiveness is spent on color, type, shape, motion, and voice.

## Generation discipline

**Diverge loose, lock late.** Generate candidate directions unstructured and over-provisioned — 5–10 internally — BEFORE imposing the decision schema; rigid templates during ideation measurably collapse diversity. Curate down to the 2–3 you render, deliberately keeping one coherent low-probability candidate as the stretch option. Persona prompts ("be creative") measurably do almost nothing — structure is the lever, not exhortation (arXiv 2501.19361 / 2510.01171).

**The self-critique gate (before rendering):** name which option is closest to the category default, and either revise it with a stated justification or justify keeping it. Then run the clone-check and the project forbidden-moves list against every option. Only then does the sheet get written.

## The pre-commitment rubric

**Tiered — full rigor only where it pays.** On consequential rungs (color, typography, north-star, signature): score each option 1–5 against each locked adjective (plus WCAG AA where text sits on color), one-line justification per score, written into the spec's working notes before presenting. On time-boxed or derived rungs: record just your recommendation and the one axis that differentiates the options — a full matrix there is busywork that erodes the habit. Two reasons the pre-commitment itself is non-negotiable:

1. **Anti-sycophancy:** judgment recorded *before* the user reacts can't be bent by their reaction (the measured bias: stated user preference inflates the model's subsequent praise of that option).
2. **Anti-drift:** scores anchored to adjectives keep round five honest when fatigue and agreement pressure peak.

Reveal order matters in both directions: the sheet itself is **neutral** (no recommendation badge — an upfront label is a measured anchor, shifts picks, and backfires when it contradicts the user's own leaning), and your recommendation plus detailed critique come *after* the user's gut reaction. Revealed first, your opinion anchors them; never revealed, it can't check them; staged, it does its job. Steering is still the job — the recommendation is always delivered, just second.

**The rebuttal rule.** Models measurably flip under user pushback, and reasoned or personalized pushback amplifies the flip (arXiv 2509.16533). When the user rebuts your critique, re-derive from the locked adjectives and your pre-committed scores *before* responding: concede only if the brief actually supports their view; otherwise hold and cite the specific locked entry. "You prefer X" is still data about them, not evidence about quality.

## Vocabulary translation table

Non-designers lack vocabulary, not insight. Translate reactions into confirm/deny levers instead of guessing or complying literally:

| They say | Candidate levers to offer |
|---|---|
| "make it pop" | contrast between title/body · accent saturation · size jump on the key element |
| "feels corporate / sterile" | warmer neutrals · rounder shapes · more personality in type · looser spacing |
| "too busy" | fewer simultaneous accents · stronger hierarchy · more whitespace · fewer borders |
| "feels cheap" | tighter type scale discipline · fewer colors · more restrained shadows · real content |
| "too boring" | one signature element amplified · bigger type contrast · a bolder accent — NOT more decoration everywhere |
| "make it blue" | ask what blue is fixing first: too warm? too playful? too low-trust? |

Record the *confirmed* translation in the spec — the reaction vocabulary becomes part of the decision record.

## The hat question

When a reaction seems to conflict with the locked adjectives or the audience, ask which hat it's from: *personal taste* or *"as my users would see it."* Both are legitimate; they're weighted differently — personal taste on a user-facing product is the most expensive feedback because nothing external checks it. When the two hats conflict, name the conflict and let the user decide wearing the right one.

## Fatigue tells and the checkpoint script

Watch for: answers getting shorter · "whatever you think" · accepting in seconds what earlier took discussion · reversing earlier reasoning without noticing. Any two → offer the checkpoint: "We've locked N decisions — good stopping point. The spec holds everything; next session picks up at [rung]. Continue or pause?" Don't lecture about decision fatigue; just make stopping free.

**Instant-accept rule:** an instant accept of a high-stakes artifact (the north-star, the full token layer) is itself a fatigue tell — offer to sleep on it before locking, even when no other tell is present.

## Session-opening re-assertion

At the start of every session (and every phase boundary), silently re-read the locked spec AND re-assert the stance: *recommendations traced to discovery, critique before comfort, trade-offs on every pick.* Agreement drift is measured behavior on long conversations — treat the stance as state that decays and needs refreshing, not a property you have.
