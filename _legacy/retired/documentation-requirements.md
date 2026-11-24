# Documentation Requirements

**Documentation is mandatory — not optional.** Every change that affects feature behavior, business rules, database/RPC contracts, or architecture MUST be reflected in `/docs/` in the same turn that ships the code. Skipping this is treated as an incomplete task, the same as skipping tests.

The trigger is **change**, not user intent: if the code touches an area documented in `/docs/`, the docs for that area must be brought back in sync. Don't wait for the user to ask.

## What triggers a mandatory doc update

| Change in code | MUST update |
|---|---|
| New feature flow, new screen, new user-visible state | `/docs/mobile/<feature>/README.md` AND `/docs/business/features/<feature>.md` |
| Existing feature behavior changed (rules, validation, flow steps) | `/docs/business/features/<feature>.md` (rules) + `/docs/mobile/<feature>/README.md` (impl) |
| Cubit/state shape change visible to the rest of the app | `/docs/mobile/<feature>/README.md` |
| New repository, RPC, or endpoint added | `/docs/business/features/<feature>.md` (contract section) |
| New business rule, invariant, or constraint | `/docs/business/<concept>.md` if cross-cutting; `/docs/business/features/<feature>.md` if feature-scoped; also update `/docs/BUSINESS_RULES.md` consolidated reference |
| Platform-level change (multi-tenancy, RLS pattern, access control, rate-limit policy) | The matching `/docs/business/<concept>.md` |
| New external package added or significant package behavior changed | `.claude/skills/documentation/packages/<package>.md` |
| Database schema change | Update relevant `/docs/business/features/<feature>.md` "Schema" sub-section. **Don't** maintain a separate schema file — the source of truth is Supabase (queried via the Supabase MCP). |

## What does NOT require a doc update

- Pure refactors that don't change behavior or public shape
- Test-only changes
- Lint/format-only changes
- Cosmetic UI tweaks (spacing, color, text wording without semantic change)
- Internal helpers renamed without changing call sites

When in doubt, update — under-documenting is worse than over-documenting.

## How to do it

After the code change is complete, update the affected docs: go through the list of changed files, classify each (feature behavior / business rule / schema / architecture / refactor-only / test-only), and update the docs that classification maps to per the structure below. For large change sets, delegate the sweep to a general-purpose subagent, passing it the changed-file list and this rule — keep the doc update as its own focused pass rather than interleaving it with feature work.

If the change is small (single-file change with an obvious doc target), update the doc inline yourself — but still update it.

## Documentation structure (canonical)

```
docs/
├── README.md                          # Navigation hub
├── BUSINESS_RULES.md                  # Consolidated rules reference
├── business/
│   ├── README.md                      # Business doc index
│   ├── invariants.md                  # ALWAYS load first
│   ├── <concept>.md                   # Platform concepts (multi-tenancy, accessibility, etc.)
│   ├── features/<feature>.md          # Per-feature business spec (canonical)
│   └── flows/<flow>.md                # Cross-cutting flows (launch, post-auth, etc.)
├── mobile/
│   └── <feature>/README.md            # Mobile implementation details
└── web/
    └── <feature>/README.md            # Web implementation details
```

`docs/database/` does NOT exist — the schema source of truth is Supabase, queried via the Supabase MCP (`list_tables`, `list_migrations`) or the dashboard.

## Feature naming

Use kebab-case for feature directories — matches URL conventions and `/docs/mobile/<feature>/`:
`auth`, `connectivity`, `force-update`, `home`, `launch`, `onboarding`, `permissions`, `terms` (current set; add to it as features ship).

## Completion check

A turn isn't complete until you can answer YES to:
- [ ] The list of files I changed maps cleanly to the docs that needed updating
- [ ] Every affected `docs/business/features/<feature>.md` / `docs/mobile/<feature>/README.md` / `docs/business/<concept>.md` has been updated OR a doc-update subagent has been spawned for them
- [ ] New features have an entry in `/docs/README.md` navigation tables
