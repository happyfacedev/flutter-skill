---
name: planning
description: Writes the implementation plan for a feature — a markdown file at `.claude/plans/<feature>.md` describing WHAT needs to be built (API contract, business rules, state requirements, UI interactions) rather than HOW to code it. Sections are organized by scope (Models / Network / Business Logic / UI), with `→ Invoke /skill-name` callouts on each step so the implementing agent loads the matching skill. Use when the user asks to plan a feature, scope a change before implementation, or break a request into agent-delegable steps. Skip for trivial changes (bug fixes, single-line tweaks, copy-only edits) — planning overhead outweighs the benefit there.
---

# Planning

A good plan answers **WHAT does the business need?** — endpoints, response shapes, request bodies, business rules, the user-facing behaviour. It does *not* prescribe class names, method signatures, or which framework to use; those are decided by the skill-following implementation agents.

The plan also serves as the contract for delegation: each section names the scope it covers, and skill-invocation callouts on each step ensure the executor loads the right templates before writing code.

## When to skip planning

Planning is overhead — the goal is to write a plan when one will pay for itself. Skip it for:
- Single-file bug fixes
- Copy-only changes (l10n, doc tweaks)
- Refactors that don't change behaviour
- Changes the user has already described step-by-step

Use planning when:
- The change spans 2+ layers (models + network + cubits + UI)
- The user asked you to plan, or scope, or break down a request
- A new feature is being scaffolded
- Multiple agents will share the work and need explicit handoff scopes

**Reconciliation with `.claude/rules/planning-workflow.md`:** the rule's "every plan MUST include..." requirements apply to plans you actually *write*. The skill decides whether a plan gets written; the rule governs the shape of plans that do. Skipping planning is not skipping the rule — it's the case where no plan exists.

## Critical Rules

1. **WHAT, not HOW.** *Why:* the implementation agents follow skills that already know HOW (Cubit shape, Freezed brick, error registry wiring, etc.). Prescribing implementation in the plan double-specifies and creates drift when the skill conventions evolve.
2. **No framework or class names in business sections.** *Why:* "create `LoginCubit`" pre-commits a shape the agent should derive from the skill. "User can submit credentials and is taken to home on success" lets the agent pick the right shape.
3. **Skill-invocation callouts ARE allowed in plan steps** (`→ Invoke /cubit-creation before writing code`). *Why:* the planning-workflow rule requires this — it's how the implementation agent knows to load the skill instead of working from memory. Skill names are meta-instructions, not implementation prescriptions.
4. **Sections are optional — include only what's needed.** A copy-only update needs no Network or Models section. A pure data-fetching change may skip UI. Use the responsibilities list (returned at the end) to declare which sections appear.

## Process

1. **Parse the request** — extract the feature, the endpoints, the data structures, the user interactions.
2. **Pick the responsibilities** — which scopes does this change actually touch? Include a scope if **new** work in that area is needed; don't include it just because a file in that area is read. E.g. "models" goes in when new response/request/failure models are added, not when an existing one is referenced.
3. **Consult the skills** that match those responsibilities (per `.claude/rules/planning-workflow.md`) so you know what conventions the implementing agent will follow — this informs the WHAT description without dragging HOW into it.
4. **Document the contract** — for each scope that applies, fill the corresponding section.
5. **Write the file** to `.claude/plans/<feature-name-kebab-case>.md`.
6. **Return** the responsibilities list + plan path to the orchestrator.

## Plan File Format

Use this template; **drop sections that don't apply**.

```markdown
# Feature: [Feature Name]

## Summary
[1-2 sentence description of what this feature does from the user's perspective.]

---

## Models Scope (drop if no new models)

### Response Models
- `[FieldName]`: `[type]` — [purpose]
- Example JSON:
  ```json
  { ... exact API response ... }
  ```

### Request Bodies
- `[FieldName]`: `[type]` — `[required/optional]` — [purpose]
- Example JSON:
  ```json
  { ... exact request body ... }
  ```

### Failure Models (if backend returns coded errors)
- `[ERROR_CODE]`: [meaning] — [when it occurs]

---

## Network Scope (drop if no API changes)

### Endpoints / RPCs
| Method | Path / RPC name | Purpose |
|--------|------|---------|
| POST | /api/... or `rpc_name` | ... |

### Error Handling
- `[Status code / error code]`: [how to surface to the user]

---

## Business Logic Scope (drop if no cubits change)

### State Requirements
- What data is tracked
- What statuses are possible (loading/success/failure or domain-specific)

### Actions
- **[Action]**: [trigger] → [outcome]
- **[Action]**: [trigger] → [outcome]

### Business Rules
- [Rule]
- [Validation]

---

## UI Scope (drop if no UI changes)

### User Interactions
- [What the user can do] → [Expected outcome]

### Display Requirements
- [What needs to be shown]
- [Loading / error / empty states]

---

## Steps (in execution order)

### Step 1: [What gets created]
→ Invoke /<skill-name> before writing code
- [Detail]

### Step 2: [What gets created]
→ Invoke /<skill-name> before writing code
- [Detail]

---

## Notes
[Any cross-section context the agents need.]
```

## Skill-invocation per step

For each step that creates a component matching a project skill, include the explicit callout — the implementation agent reads steps as instructions, not as user requests, so skill descriptions don't trigger automatically.

| Step creates... | Add to step |
|-----------------|--------------|
| Cubit / state class | `→ Invoke /cubit-creation before writing code` |
| Form input / form cubit / form-aware page | `→ Invoke /form-creation before writing code` |
| Data model (Freezed) | `→ Invoke /model-creation before writing code` |
| Failure class / mapper | `→ Invoke /failure-modeling before writing code` |
| REST API client / repo | `→ Invoke /network-creation before writing code` |
| Supabase repository | `→ Invoke /network-creation-supabase before writing code` |
| Page (`features/<x>/ui/pages/`) | `→ Invoke /page-creation before writing code` |
| Reusable / extracted widget | `→ Invoke /widget-creation before writing code` |
| Route entry (`AppRoutes` / `GoRoute`) | `→ Invoke /navigation-gorouter before writing code` |
| App-lifetime singleton or pre-`runApp` init | `→ Invoke /bootstrap-composition-root before writing code` |
| New env-driven value or per-tenant config | `→ Invoke /env-config-flavors before writing code` |
| Deeplink target / deeplink host + scheme config | `→ Invoke /deep-link-handling before writing code` |
| `AuthRepository` operation / Supabase auth event mapping | `→ Invoke /auth-flow-supabase before writing code` |
| Unit / bloc test | `→ Invoke /unit-testing before writing code` |
| Any new code-gen annotation (`@freezed` / `@injectable` / `@Generate` / `@RestApi` / `@HiveType`) | `→ Invoke /code-generation-workflow after writing code` |

## Return Format

After writing the plan file, return this exactly to the orchestrator:

```
RESPONSIBILITIES: [comma-separated, e.g., "models, network, business_logic"]
PLAN_PATH: [e.g., ".claude/plans/login-feature.md"]
```

Only include responsibilities whose section actually exists in the plan.

## Decision Criteria

Include a responsibility only when **new** work in that area is needed (modifying an existing model doesn't count unless the modification is non-trivial).

**Include "models" if:** new response/request body model is added, or backend introduces new coded errors.

**Include "network" if:** any new endpoint, new RPC, or change to error routing.

**Include "business_logic" if:** a new cubit is added, or an existing cubit's state shape / actions change non-trivially.

**Include "ui" if:** user-facing pages or widgets are added, or existing layouts change non-trivially.

**Edge cases:**
- Features with no UI (background sync, analytics consent) — drop the UI section; the section list shrinks accordingly.
- Features with no network (pure data transformation in a cubit, theming) — drop network and models.
- Cross-feature signalling (cubit A in feature X fires a `simple_refresh_bus` event that cubit B in feature Y listens to) — note it in the Business Logic Scope under "Cross-feature dependencies"; there's no separate section for it.

## Example: Good vs Bad Plan Content

### ❌ Bad — implementation-focused
```
Create LoginCubit with login() method that calls LoginRepository.
Use Freezed for LoginResponse model with token and user fields.
```

### ✅ Good — business-focused
```
## Business Logic Scope

### State Requirements
- Track authentication status
- Store user profile after successful login
- Store token for future requests

### Actions
- **Login**: user submits email/password → authenticate, store session
- **On failure**: show error message based on error type

### Business Rules
- Email must be valid format
- Password is required
```

The Steps section can still say `→ Invoke /cubit-creation` — that names a *skill*, not a class. The skill picks the class shape.

## Checklist

- [ ] No framework or class names appear in business sections
- [ ] Each section that's present has substance; empty stubs were dropped
- [ ] API structures (responses + request bodies) are preserved exactly as JSON
- [ ] Business rules live in Business Logic Scope, not scattered
- [ ] Every endpoint appears in Network Scope
- [ ] Every backend error code that the UI cares about is documented
- [ ] Each step has a `→ Invoke /<skill-name>` callout if it creates a skill-covered component
- [ ] Plan file written to `.claude/plans/<feature-name>.md` (kebab-case)
- [ ] Responsibilities list returned matches the sections actually present in the plan
