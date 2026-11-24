# Component inventory — the completeness spine

The union of Material 3, Apple HIG, Shopify Polaris, IBM Carbon, Ant Design, Atlassian, and Uber Base, filtered to mobile relevance. In Phase 6, walk every category; every component the app needs gets variants + states decided; everything else gets an explicit N/A. **A component is not decided when its default is drawn — it's decided when every applicable state is.**

**Open with the flow, not the spine.** Phase 6 opens with an **interface inventory of the locked north-star flow** (Brad Frost's method applied to our own artifact): list every distinct element the flow's screens actually contain, and decide those components first. Then walk the category spine below as the completeness backstop for whatever the flow didn't surface. Components the flow proved are never N/A'd.

## The state matrix

Framework-free states that must be *explicitly designed* wherever they apply:

| State | Applies to |
|---|---|
| enabled (default) | everything |
| pressed (ripple/feedback) | every interactable |
| disabled | every interactable |
| focused | inputs, plus keyboard-reachable controls |
| **loading** | buttons that submit, async containers |
| **error** | inputs, async containers, submissions |
| success/valid | inputs with async or high-stakes validation |
| selected | chips, tabs, rows, cards, nav items, toggles |
| empty/placeholder | inputs, async containers, lists |
| read-only | inputs displaying non-editable data |
| indeterminate | checkboxes (tri-state), progress |

**Every async surface has four data states — loading / loaded / empty / error — plus offline on mobile.** Each is a designed decision, not an afterthought.

**A state is decided when its VALUE is recorded** — colors/borders/opacity/copy, or an explicit pointer to the approved artifact that shows it. A named state with no value is UNDECIDED.

## Categories

**1. Actions** — button (primary / secondary-outlined / ghost-text / destructive / link), icon button, FAB (if Material-leaning), segmented control, menu/dropdown trigger. Buttons carry loading + disabled behavior *inside* the component.

**2. Text inputs & data entry** — text field (single + multiline), password (reveal), search, number/stepper, select/dropdown, multi-select, autocomplete, checkbox (+group), radio (+group), switch, slider, **date picker, time picker, date-range** (the most-skipped, highest-edge-case components: locale format, min/max, invalid-date feedback), file/image picker, rating, form layout + inline field error + helper text. Full input state row: empty, focused, filled, disabled, read-only, error(+message), success, loading, with prefix/suffix icon, character count.

**3. Selection & display** — chip/tag (input, filter/choice, status), badge (count + dot), avatar (+fallback initials), icon conventions, thumbnail/image container (+ broken-image fallback).

**4. Containment & structure** — card (list-row, standalone, selectable, hero), list item/tile (the highest-frequency component in most apps — Airbnb's #1 retro regret was under-investing in rows; spec it early and thoroughly), divider, accordion/expansion, key-value/description row, stat/metric display, table (if data-heavy).

**5. Navigation** — app bar (title, leading/back, action slots), bottom navigation bar (+ badge treatment), tabs, drawer (if used), stepper/progress-steps, link treatment, pagination or infinite-scroll policy.

**6. Overlays** — dialog/alert (incl. **destructive-confirm** pattern), bottom sheet (modal + persistent; drag handle, top radius), popover/menu surface, tooltip (if any), **toast/snackbar as a managed system** — stacking, timing, action slot, dismiss, success/error/info variants.

**7. Feedback & status** — inline banner (info/success/warning/error), full-page result (success / failure / 404-ish), **empty states — four distinct types, each with its own copy + CTA**: first-use, user-cleared, no-results, error/offline. Empty state = component with slots: illustration, headline, body, primary CTA, secondary CTA. Empty/error/loading copy derives from the Voice & microcopy rung's tone matrix — never improvised per-surface.

**8. Progress & loading** — spinner (short blocking ops), linear/progress bar (known duration), **skeletons for content loads** (near-unanimous over spinners for lists/feeds/dashboards; don't skeleton <300ms), pull-to-refresh (mobile-only — no web system specs it; decide it explicitly), stepped progress.

**9. Typography-as-component** — whether text roles are enforced through a Text-style component/API or discipline alone (Polaris ships a Text component precisely to make the scale unbreakable).

**10. Identity & media** — logo usage rules, image placeholders (blurhash/solid/initials), aspect-ratio conventions, avatar sizes.

**11. Layout primitives** — page envelope (scaffold + safe area + page padding), section header, gap/stack conventions — mostly decided by tokens; confirm nothing page-level is left to improvisation.

**12. Charts & maps** (when the data-viz rung isn't N/A) — chart frame (axis, gridlines, labels, legend), tooltip/scrub interaction, per-chart-type components (line / area / bar / sparkline, as needed), map surface (tile styling matched to the neutral ramp, route/marker treatment, chrome buttons) — each with the four data states + no-data / no-sensor fallbacks. Empty/error copy for these comes from the Voice rung's tone matrix.

## The last 10% — the forgotten list

Walk this explicitly at the end of Phase 6; these are the documented industry blind spots:

- Date/time/range pickers (leap years, locale formats, bounds)
- Toast system behavior (not just its look)
- Permission-priming dialogs (the screen BEFORE the OS prompt: notifications, location, camera)
- Image/avatar fallbacks and broken-image states
- Empty search results vs empty collection (different copy, different CTA)
- Per-component skeletons
- Offline banner + cached-data indicator + retry affordance
- Long-content truncation policy (ellipsis vs fade vs expand)
- RTL behavior, dynamic type / large-font-scale behavior
- Destructive-action confirmation flow
- Keyboard avoidance / inset behavior for forms

## Audit method (when overhauling an existing app)

Interface Inventory (Brad Frost): screenshot every unique UI element across the current app, group by category above, lay them side by side. The duplicates and near-duplicates ARE the findings — each cluster becomes one decided component. Expect the first pass to miss things; do a second pass after Phase 6's walk.
