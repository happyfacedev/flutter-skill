# Elicitation toolbox — extracting taste from someone who "knows it when they see it"

Techniques, ordered by when they enter the session. The common thread: **recognition beats recall** — people who cannot generate a preference can reliably pick between two things they can see.

## Adjective exercise (Phase 1 opener)

Brainstorm freely — including controversial or silly words (they force differentiation). Then sort every candidate into **You are / You are not / Doesn't apply**. Cluster the "are" pile into three buckets so visual words don't blur with voice words:

- **Presentation** — visual style, color, light, polish
- **Tone** — voice, friendliness, authority
- **Personality** — expert-like, playful, calm

Cap ~4 per bucket; distill to the final 3–5. **Store each survivor polarized — "X, not Y"** — where Y is the rejected but genuinely *appealing* opposite from the forced-choice run below (never a strawman), plus a one-line "rules out:" note naming what the choice forecloses. Apply Spool's two tests to each: a good adjective lets you say *no* roughly two-thirds of the time, and a good competitor would plausibly choose the reverse — if no competitor would, it isn't a decision ("clean", "modern" fail both). Then collect one competitive-positioning statement: "unlike [competitor A] and [B], we lean [Z]".

## Forced choice between opposing appealing traits

The strongest single technique. Present pairs where BOTH options are attractive and genuinely opposed — the opposite of *daring* isn't *dull*, it's *reliable*; the opposite of *warm* isn't *cold*, it's *precise*. Choosing between two good things reveals actual priority; choosing between a good and a bad thing reveals nothing. Run 6–10 pairs, record the picks and any hesitations (hesitation = a real tension worth discussing). Each pair feeds the polarity format directly: the winner is the stored X, the loser is the recorded "not Y" — which is exactly why the loser must be a genuinely appealing trait, not a strawman.

## Spectrum / comparison statements

"More like [A] than [B]" against brands and apps the user knows: *more like Linear than Notion; more like a espresso bar than a family diner; more like Google than Apple.* Comparative anchors are far easier for non-designers than abstract adjectives, and they compress a hundred micro-decisions into one gestalt. Collect 5–10; contradictions between statements are findings, not noise — surface them.

## Reference ranking + anti-references

Have the user collect 3–7 admired apps/screens (their phone, Mobbin, Dribbble) and RANK them, saying one sentence about why each earns its rank. Then explicitly: **"what must this app NOT look like?"** — anti-references carve the space faster than positive ones and are usually delivered with more conviction. Store everything in `design/refs/`.

## Steal-from-one-reference constraint

For a user spiraling across too many inspirations: pick ONE primary reference, take its *structure* — spacing, density, navigation patterns, hierarchy — and explicitly discard its colors and copy. The single-source constraint prevents incoherent mashups while the personality adjectives keep it from becoming a clone.

## This-or-that mock pairs

When a ladder rung stalls: render the SAME element (a card, a button row, a header) both ways — two radii, two densities, two hues — as an option sheet (`templates/option_sheet.html`) and ask which. Never more than three variants; the sheet stays neutral and your recommendation comes in chat *after* the gut reaction (staged reveal — canonical rules in `collaborator-discipline.md`). This is the north-star screen technique applied at micro scale — and it is the default form of every visual question, not a fallback.

## Reading disagreement (multi-stakeholder case)

If more than one person sorts the adjective cards, photograph/record each person's layout separately — **the disagreements between stakeholders are as valuable as the traits**. A trait one founder puts in "are" and the other in "are not" is the first conversation to have, before any pixels.

## Anti-patterns

- **Open-ended polling** ("what colors do you like?") — produces bland superlatives and stalls.
- **Never giving a recommendation at all** — offloads the design decision onto the person who hired a collaborator precisely because they can't make it; invites Frankenstein combinations ("header from A, colors from B"). The recommendation is always delivered — staged after the gut reaction, not printed on the sheet.
- **More than 3 simultaneous options** — dilutes your recommendation and overwhelms.
- **Accepting "I like all of them"** — force the ranking; ties are refusals to decide.
- **Mistaking silence for approval** — every lock needs the user's explicit words.
- **Priming before first exposure** — "notice the typography" before they've seen the sheet kills the authentic gut reaction; direct attention only after the first which-and-why.
