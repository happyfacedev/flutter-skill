---
name: documentation
description: The workflow for keeping `/docs/` in sync with code changes — what to update in `docs/business/features/<feature>.md`, `docs/mobile/<feature>/README.md`, `docs/business/<concept>.md`, `docs/BUSINESS_RULES.md`, and `docs/README.md` after a code change ships. Also the lookup index for project-internal package references in `packages/`. Use proactively after any change to feature behavior, business rules, schema, or architecture (per `.claude/rules/documentation-requirements.md`, doc updates are mandatory, not optional). Use also when the user asks "how does X work", "what is the flow for X", or needs to find which doc owns a topic.
---

# Documentation

Documentation in this project is **mandatory** — every behavior-affecting change must update the corresponding `/docs/` file in the same turn. The enforcement lives in `.claude/rules/documentation-requirements.md` (always loaded). This skill is the workflow: how to find the right doc, what to put in it, and when to spawn the `documentation-updater` agent.

## Documentation map

```
docs/
├── README.md                          # Navigation hub — features table lives here
├── BUSINESS_RULES.md                  # Consolidated business rules (cross-feature reference)
├── business/
│   ├── README.md                      # Index of platform spec
│   ├── invariants.md                  # Cross-cutting rules. Read first.
│   ├── multi-tenancy.md               # Organization tenancy; per-tenant config
│   ├── access-control.md              # Permission catalogue & roles
│   ├── accessibility.md               # WCAG 2.1 AA baseline
│   ├── concurrency.md                 # Isolation, locks, retry policy
│   ├── rate-limiting.md               # Sliding-window limiter spec
│   ├── observability.md               # Logging, error reporting, PII
│   ├── platform-tiers.md              # SaaS tiering for tenants
│   ├── schema-changes.md              # DB schema deltas required by flows
│   ├── terminology.md                 # Shared vocabulary
│   ├── open-questions.md              # Tracked unresolved decisions
│   ├── features/<feature>.md          # Per-feature business spec — canonical
│   └── flows/<flow>.md                # Cross-cutting flows (launch, post-auth, account-lifecycle)
├── mobile/<feature>/README.md         # Mobile implementation (arch, cubits, repos)
└── web/<feature>/README.md            # Web implementation (where applicable)
```

`/docs/database/` does NOT exist — the schema lives in Supabase. Query it via the Supabase MCP (`list_tables`, `list_migrations`) or the dashboard. If a schema concern is feature-specific, put it in `docs/business/features/<feature>.md` under a Schema sub-section.

## Where does a change get documented?

| Change | Update | Notes |
|---|---|---|
| New feature ships | `docs/business/features/<feature>.md` + `docs/mobile/<feature>/README.md` + `/docs/README.md` nav table | Both layers + nav entry |
| Existing feature behavior changes | `docs/business/features/<feature>.md` (rules) and `docs/mobile/<feature>/README.md` (impl) | Either or both depending on what changed |
| Cubit / state / repository shape changes | `docs/mobile/<feature>/README.md` | Impl layer only |
| New business rule / invariant | `docs/business/features/<feature>.md` (feature-scoped) OR `docs/business/<concept>.md` (cross-cutting). Also reflect in `docs/BUSINESS_RULES.md` consolidated reference | |
| Platform-level concept change | `docs/business/<concept>.md` — e.g. multi-tenancy, access-control, rate-limiting, accessibility | |
| Cross-cutting flow change | `docs/business/flows/<flow>.md` — e.g. launch sequence, post-auth gating, account lifecycle | |
| External package added / behavior changes | `.claude/skills/documentation/packages/<package>.md` | Internal reference for the project's package ecosystem |
| Schema change | `docs/business/features/<feature>.md` Schema sub-section. Don't duplicate the schema; describe what the feature depends on and link to the Supabase table by name. | |

## Workflow

After the code change is done — and after any post-review fixes have also landed:

1. **Identify the affected docs** using the table above. List them explicitly — "this change touches `docs/business/features/organization.md` and `docs/mobile/organization/README.md`".
2. **Default to spawning the `documentation-updater` agent**. It reads the rule, walks the change set, identifies affected docs, and updates each. This is the right path even for "small" changes — it's the way you avoid forgetting one of the three places a rule needs to land.
3. **Inline edit is allowed only when ALL three are true**: exactly one doc file is affected, you have read that doc in the current turn, and the edit is a single paragraph or table-row change. Anything broader → spawn the agent.
4. **If code-review triggered additional code changes**, re-run the doc update over the post-review change set. Docs reflect the final state of the code, not the pre-review state.
5. **Verify**: the doc accurately describes the new behavior, links resolve, navigation table in `/docs/README.md` is current for any new feature, and `docs/BUSINESS_RULES.md` consolidated reference reflects any new rule.

## Feature README template (mobile/<feature>/README.md)

```markdown
# <Feature>

> One-paragraph summary of what the feature does from the user's perspective.

## Overview

What the feature does and why.

## Business Rules

The constraints that govern behavior. For complex features, link to `docs/business/features/<feature>.md` rather than duplicating.

## User Flows

Step-by-step user journeys (sign-up flow, purchase flow, etc.).

## Mobile Implementation

- **Cubits / state**: which cubits manage this feature, what state they hold
- **Repositories**: which repos back this, which RPCs / endpoints
- **Failures**: feature-specific failure hierarchy if any
- **Page structure**: top-level pages and their relationships
- **Integration points**: cross-cutting concerns this feature touches (refresh bus, scope context, etc.)

## Related Features

Links to features this one depends on or affects.
```

## Business feature spec template (business/features/<feature>.md)

The business specs follow a precondition → trigger → steps → postcondition shape. Each file starts with a `## Related` block linking dependencies / affects / shared invariants. See any existing file (e.g. `docs/business/features/organization.md`) for the full convention.

## Internal package reference

The `packages/` subdirectory documents the project's own external-package ecosystem (the workspace packages, not pub.dev dependencies). When a package's behavior changes, update the matching file:

- [packages/auth.md](packages/auth.md) — user authentication & session management
- [packages/form-inputs.md](packages/form-inputs.md) — form field validation
- [packages/theme.md](packages/theme.md) — theme utilities & sizing
- [packages/localization.md](packages/localization.md) — i18n support
- [packages/shared-core.md](packages/shared-core.md) — common utilities

## When the user asks "how does X work"

Use this skill as a lookup tool:

1. Cross-cutting concept (multi-tenancy, access control, accessibility)? → `docs/business/<concept>.md`
2. Feature business rules? → `docs/business/features/<feature>.md`
3. Mobile implementation? → `docs/mobile/<feature>/README.md`
4. Cross-cutting flow (launch, post-auth)? → `docs/business/flows/<flow>.md`
5. Single rule reference? → `docs/BUSINESS_RULES.md`
6. Platform invariants? → `docs/business/invariants.md` (always relevant)

> **Note**: docs are kept in sync per `.claude/rules/documentation-requirements.md`, but verify schema details against Supabase directly if the change is recent — the MCP is the source of truth.

## Checklist

- [ ] Identified every doc affected by the change (used the table above)
- [ ] For new features: entry added to `/docs/README.md` navigation table
- [ ] For new features: both `docs/business/features/<feature>.md` AND `docs/mobile/<feature>/README.md` created
- [ ] Existing docs touched preserve their structure and conventions
- [ ] Schema details reference Supabase tables by name — not duplicated as separate files
- [ ] Links between docs (Related blocks, navigation) still resolve
- [ ] Consolidated `docs/BUSINESS_RULES.md` reflects any new business rules
