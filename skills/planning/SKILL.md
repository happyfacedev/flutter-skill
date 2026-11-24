---
name: planning
description: Internal flutter-skill pattern — invoked via the flutter-skill router, not from this description. (Feature plans — WHAT, not HOW.)
---

# Planning

A plan is the **business contract** for a multi-layer change: WHAT the feature needs — endpoints, data shapes, business rules, user-facing behavior — never HOW to build it. The routed patterns already know HOW; a plan that prescribes implementation double-specifies and drifts from them as conventions evolve.

The same shape applies whether the plan lives in a plan-mode message or a file. Write a file (`.claude/plans/<feature-kebab>.md`) only when the user asks for a plan document or the work will hand off across sessions.

## When to plan

Plan when the change spans two or more layers (models + network + cubits + UI), scaffolds a new feature, or the user asks to plan, scope, or break down a request.

Skip planning for single-file bug fixes, copy-only changes, refactors that don't change behavior, and changes the user already described step-by-step. Planning is overhead — write a plan only when it pays for itself.

## Critical Rules (Never Break)

1. **WHAT, not HOW.** Business sections state needs — "user submits credentials and lands on home on success" — never class names, method signatures, or framework choices ("create `LoginCubit` with `login()`"). *Why:* the executor reads plan steps as user intent, so a plan-time shape wins over the pattern's shape — and the two drift apart as patterns evolve. The pattern decides the shape at build time.

2. **Preserve contracts verbatim.** API responses and request bodies go into the plan as exact JSON; backend error codes as an exact list with meanings. *Why:* paraphrased contracts get re-invented at implementation time — field names and nesting mutate between plan and code.

3. **Every step that creates a component carries its pattern callout** — `→ Invoke /<pattern> before writing code` — with the pattern taken from the **router's routing table**. This file deliberately carries no copy of that table. *Why:* patterns are matched against user requests, not plan steps; the callout is what makes the executor load the pattern mid-plan. And a second step→pattern mapping would rot — the router table is the single routing authority.

4. **Sections are scoped and optional.** Include a section only when **new** work exists in that scope — referencing an existing model doesn't put "Models" in the plan. *Why:* empty scaffolding sections invite invented work to fill them.

## Plan shape

Drop any section without new work.

```markdown
# Feature: <name>

## Summary
[1–2 sentences, from the user's perspective.]

## Models scope
- Response / request fields: name, type, purpose — plus the example JSON, verbatim.
- Backend error codes: `[CODE]` — meaning, when it occurs.

## Network scope
- Endpoints / RPCs: method, path or RPC name, purpose.
- Error handling: which codes surface to the user, and as what.

## Business logic scope
- State requirements: what is tracked, which statuses are possible.
- Actions: [trigger] → [outcome].
- Business rules and validation.

## UI scope
- User interactions: [what the user does] → [expected outcome].
- Display requirements, including loading / error / empty states.

## Steps (dependency order)
### Step 1: <what gets created>
→ Invoke /<pattern> before writing code
- [detail]

## Notes
[Cross-section context the executor needs.]
```

## Example — the WHAT-not-HOW line

❌ **Bad (implementation-focused):**
> Create LoginCubit with a login() method calling LoginRepository. Use Freezed for LoginResponse with token and user fields.

✅ **Good (business-focused):**
> **State requirements:** track authentication status; store the session after success.
> **Actions:** Login — user submits email/password → authenticate, store session, land on home.
> **Business rules:** email must be valid format; password required.

The step still says `→ Invoke /cubit-creation before writing code` — that names a *pattern*, not a class. The pattern picks the shape.

## Checklist

- [ ] No class, method, or framework names in business sections
- [ ] Response and request JSON preserved exactly; every user-relevant error code listed with its meaning
- [ ] Each component-creating step has its `→ Invoke /<pattern>` callout, mapped via the router's routing table
- [ ] Sections without new work were dropped
- [ ] Steps are in dependency order (typically models → network → business logic → UI)
- [ ] Plan written to `.claude/plans/<feature-kebab>.md` only if a document was requested or work spans sessions
