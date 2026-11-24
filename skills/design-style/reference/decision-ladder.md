# The direction ladder — 14 decisions, in dependency order

Each decision: what it is · inputs · how to propose · safe default (for a user with no strong pull) · decided when. The order is load-bearing: personality constrains platform bias constrains color… Deciding a lower rung first is the canonical mistake (every major design language went principles → type+color → everything else).

## 1. Platform bias

**What:** how native vs branded the app feels — Material, Cupertino, adaptive-per-platform, or fully custom.
**Inputs:** target audience's platform expectations; how much brand distinctiveness the product needs; team capacity (fully custom = every component hand-specified).
**Propose:** frame as "we follow [system] except where brand overrides" — the exceptions list IS the brand.
**Safe default:** Material bones with custom skin (our stack's natural fit) — platform conventions for navigation/gestures, brand for color/type/shape.
**Decided when:** the sentence "we follow X except …" is written and locked. This gates shape, motion, and component defaults below.

## 2. Color temperature + palette strategy

**What:** warm vs cool; the palette strategy (monochrome / single-accent / analogous / complementary); THE one primary brand hue everything derives from; how neutrals are tinted.
**Inputs:** personality adjectives (trust/finance → blue-cool; premium → deep+gold; playful → saturated warm); brand givens; competitor palettes (differentiate or conform?).
**Propose:** an option sheet — the same mini screen rendered under 2–3 candidate primary hues (with a dark strip each), never color names or bare swatches. State the temperature rule: neutrals tinted warm OR cool (<5% saturation), never mixed.
**Safe default:** single-accent — one brand hue + one neutral ramp + the four status hues. The safest non-designer strategy and the easiest to keep coherent.
**Decided when:** primary hue hex + strategy name + neutral temperature are locked. (Full ramps are Phase 4 work — this rung is direction only.)

## 3. Typography

**What:** 1–2 typefaces (hard max two) and the personality they carry. Often the single most identity-defining decision at scale (Stripe/Söhne, Uber Move).
**Inputs:** personality; platform bias (SF/Roboto read native); licensing pragmatics — app embedding rights, variable-font availability; script coverage for the app's locales.
**Propose:** fast path first — default to ONE family (a variable font or superfamily) and get contrast from weight/width/x-height before reaching for a second family; a two-family pairing only when a personality contrast genuinely demands it (Google Fonts Knowledge / Refactoring UI consensus). Then an option sheet with the candidate typefaces actually loaded (Google Fonts link or local files) and rendered at real scale — page title, section header, body paragraph, caption — per option. Consider: system font for body + character font for display (perf + safety), or one superfamily (Plex, Source, Noto) for guaranteed pairing. Flag: Inter is the overused "safe" default — fine, but it makes no statement.
**Safe default:** one variable font, body + display from the same family, 2–3 weights.
**Decided when:** family name(s) + weight set + variable-vs-static locked. (The scale ratio and role set are Phase 4.)

## 4. Voice & microcopy

**What:** the verbal identity — 2–3 voice principles derived from the adjectives; a tone-by-state matrix (voice never changes, tone does — Mailchimp's rule: calm/supportive in errors, quiet in success, encouraging in empty states); a casing policy (interacts with typography's caps treatment); the number/unit/date formatting voice.
**Inputs:** the personality adjectives; category conventions; the app's domain vernacular.
**Propose:** a text-form decision (one of the few non-visual rungs) — the principles + the tone matrix + 5–6 sample strings (error, empty, success, permission ask, destructive confirm) written in the candidate voice. The sample strings then appear in later option sheets and component sheets, so the voice is judged in situ, not in the abstract.
**Safe default:** plain, direct, sentence case, no exclamation marks; errors state what happened + the next step.
**Decided when:** principles + matrix + casing locked; every later empty/error/permission string must be derivable from them.

## 5. Density

**What:** compact vs comfortable vs spacious; the base spacing unit.
**Inputs:** data-richness (dashboards/tables → compact; consumer/content → comfortable); audience (older users → spacious); personality ("calm" and "dense" rarely coexist).
**Propose:** an option sheet — the same list screen rendered at two densities.
**Safe default:** 8px base with 4px half-steps, comfortable tier. (4px base only for genuinely dense/pro UIs.)
**Decided when:** base unit + tier named. Drives every padding decision in Phase 4.

## 6. Shape language

**What:** the radius personality — sharp ↔ subtly-rounded ↔ friendly ↔ pill-heavy.
**Inputs:** personality via the Bouba/Kiki mapping — 2–4px reads professional/minimal, 8–12px friendly/modern, heavy rounding playful; sharp corners read formal/technical. Platform bias (M3 defaults pill buttons).
**Propose:** an option sheet — the same card + button + field at 2–3 radius personalities, side by side.
**Safe default:** moderate (buttons ~12–14, cards ~16, pill for chips/avatars).
**Decided when:** the personality is named and sample values for control/card/pill agreed. Document the nested-radius law now: **inner radius = outer radius − parent padding**, never equal.

## 7. Iconography style

**What:** ONE icon family, one style (outlined / rounded / filled), one stroke weight. Mixing sets is the classic non-designer tell and the top community regret ("Frankenstein UI").
**Inputs:** shape language (rounded icons with rounded UI); density (filled reads faster at small sizes); platform (Material Symbols / SF Symbols read native — note SF Symbols is Apple-only licensed).
**Propose:** an option sheet showing the SAME 6 icons (home, search, settings, back, add, error) from each candidate set, inlined as SVG at the workhorse size. Common picks: Lucide (safe, MIT, 1.5px stroke), Material Symbols (variable axes), Phosphor (multi-weight).
**Safe default:** outlined as baseline + filled for active/selected states, from one set.
**Decided when:** set + style + the active-state convention locked.

## 8. Illustration style

**What:** flat / geometric / 3D / hand-drawn / none; must reuse the app palette.
**Inputs:** personality; budget reality (custom illustration is expensive to keep consistent — an empty-state pack may be all the app needs).
**Propose:** an option sheet — the same empty-state slot on the mini screen rendered with each candidate style (real sample illustrations, inline SVG or sourced images in `design/refs/`), never prose descriptions of a style.
**Safe default:** N/A or a minimal geometric spot-illustration style constrained to palette colors — decide where illustrations appear (empty states, onboarding) and nowhere else.
**Decided when:** style reference + usage surfaces locked, or N/A with reason.

## 9. Photography treatment

**What:** whether photos appear, and their grade/mood/crop conventions if so.
**Inputs:** does the product inherently show photos (user content, products, food)? Personality → treatment (warm/candid vs cool/editorial).
**Propose:** an option sheet — the same real photo rendered under each candidate treatment (grade/crop/container) on the mini screen.
**Safe default:** N/A for utility apps; for photo-bearing apps: define the container treatment (radius, aspect ratios, fallback placeholder) even if grading is uncontrolled user content.
**Decided when:** treatment spec or N/A locked. Image fallback/placeholder behavior noted for Phase 6.

## 10. Data-visualization language

**What:** how quantitative data looks and behaves — the chart types in use, the encoding palettes, the axis/gridline/legend/tooltip/no-data conventions, and the map treatment if maps exist.
**Inputs:** the §0 surface inventory (which chart/map surfaces actually exist); the color rung (palettes derive FROM the brand direction but are distinct from both the brand accent AND the status hues — collision with success/error is the classic trap); density.
**Propose:** an option sheet — the same real chart (a real data curve) rendered under 2–3 encoding strategies (e.g., single-hue + emphasis vs categorical multi-hue vs monochrome heat), with the no-data state alongside. Constraints to record (Carbon's method): categorical palettes sequenced for maximum neighbor contrast; 3:1 non-text contrast (WCAG 1.4.11); colorblind-safe (verify with a simulator); scale gracefully 2→8 categories; sequential/diverging ramps for magnitude data; gridlines minimal and never darker than the data.
**Safe default:** N/A for apps with no quantitative surfaces; else single-hue emphasis (accent for the focal series, neutrals for context) — the safest non-designer strategy.
**Decided when:** palette values + per-chart-type conventions + no-data treatment locked, or N/A. Full palette construction → `token-construction.md`.

## 11. Motion personality

**What:** how the app moves — snappy-productive vs expressive-playful; the default easing character.
**Inputs:** personality (financial/professional → crisp, restrained, ease-out; playful → springy, bouncy); platform bias.
**Propose:** a replayable option sheet — the same element (card entering, sheet rising, button feedback) animated under each personality's actual durations and curves, with replay buttons; motion is the least describable decision of all.
**Safe default:** productive/snappy. The community signal is loudly anti-over-animation: motion on frequent, repeated actions must be near-invisible.
**Decided when:** personality named + 2–3 motion principles written (à la Slack "purposeful, clear, delightful"). Token values are Phase 4.

## 12. Light/dark strategy

**What:** light-first, dark-first, or both; which is the *primary* design target; whether any surfaces are theme-independent.
**Inputs:** use context (night/entertainment → dark matters; productivity/content → light-first); brand color fidelity (brand hues read truer on light); OLED.
**Safe default:** support both, follow system, design light-first — and decide NOW whether auth/onboarding surfaces are theme-independent (our two-family widget split flows from this).
**Decided when:** primary mode + support matrix + theme-independent surfaces list locked. Dark rules to record: never pure black (#121212-region base), desaturate accents, elevation = lighter surfaces not shadows.

## 13. Platform surfaces & feedback

**What:** the brand at the OS boundary — app icon (+ Android adaptive layers, notification icon), splash/launch, notification & live-activity/Dynamic-Island appearance, status-bar/system-UI style, haptic language (which interactions get which intensity), audio cues (or none), keyboard appearance.
**Inputs:** the §0 surface inventory (N/A whole items the app lacks); the light/dark rung; the signature candidates.
**Propose:** icon/splash as an option sheet (the icon at real sizes — 48/29/180px on a real home-screen strip); the rest mostly text-form with reference examples.
**Safe default:** icon derived from the signature element or the wordmark initial; splash = canvas color + logo, no animation; haptics: light impact on primary confirm only; status bar follows theme.
**Decided when:** each sub-item has a value or an explicit N/A.

## 14. Signature element

**What:** the one recognizable thing that makes any screenshot identifiably this app — a gradient language (Stripe), a shape motif, a typographic gesture, a distinctive component treatment.
**Inputs:** everything above; the brand's existing equity.
**Propose:** only after 1–13 are locked — the signature must be an amplification of the direction, not a bolt-on. Form: an option sheet rendering each candidate signature ON the mini screen (the gradient applied to the primary surface, the shape motif in place) — a signature described in prose isn't a proposal.
**Safe default:** N/A is honest for utility apps; a restrained signature (e.g., one gradient treatment on primary surfaces) is the low-risk version.
**Decided when:** the element + its usage rule ("appears on X, never on Y") locked, or N/A.

## Safe visual rules (defaults bank)

When the user has no opinion, these community-consensus rules are safe to adopt silently (cite: Hobday's safe rules, Refactoring UI, HN non-designer threads):

- Never pure black on pure white; near-black text on near-white surfaces.
- Max two typefaces; create hierarchy with size/weight before adding fonts.
- More space *around* an element than *inside* it groups content correctly.
- Saturated color for meaning, neutrals for structure; constrain the palette hard.
- Data colors are never UI-chrome colors — containment keeps dashboards from turning into rainbow chrome.
- Shadows don't work on dark UIs — use surface lightness for depth.
- One icon style, one stroke weight, everywhere.
- Numeric floors (type sizes, line-heights, spacing-step ratios, contrast) live in `token-construction.md` — one home for the numbers, no drift.
