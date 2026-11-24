# Feature scaffold — spec → stamp → fill → gate

For standard features, do NOT hand-write the standard files. You describe the feature's data contract in a small JSON spec; the generator stamps everything mechanical (repository with the wide seam, cubit + state, pages, failures, widgetbook use cases with real sample data, passing tests, routes, localization keys) and prints the exact list of what remains for you.

## Scope — check this FIRST

**Requires the kit's project layout.** The stamp imports `lib/core/` files it does not create (widgets such as `TopBar`, `EmptyState` and `ErrorState`, theme extensions, router, injection). In a project without them the output does not compile — use the normal pattern skills instead.

**CAN (use the spec flow):**
- A NEW feature: read-only list page, optionally + detail page
- One NEW repository, Supabase table reads (list + single-by-id), optional ordering
- **Action mutations by id**: `delete` (row delete) and `action` (update with FIXED column assignments — mark-read, archive, cancel), optionally confirm-gated. Stamped: repo method, guarded cubit action that reloads the list on success, own failure + copy, 4 tests each
- **RPC sources** on any operation: `"source": { "rpc": "backend_function" }` for list, plus `"idParam": "p_row_id"` for single/delete/action — when the backend exposes a function instead of direct table access. The row id is the ONLY parameter supported. single/delete/action RPCs must return a single row / void — a `RETURNS SETOF/TABLE` function yields a list and fails the stamped cast; declare those as `list` or fall back to the pattern skills
- Standard request/response cubit(s), feature failures with localized copy
- Routes, widgetbook use cases, cubit tests, ARB keys — all generated

**CANNOT (fall back to the normal pattern skills — this is the sanctioned path, not a failure):**
- Create/edit **forms** (that's `/form-creation`), query filters, toggle-from-current-value, optimistic updates, per-item loading states
- RPC calls needing parameters beyond the row id (org context, payloads, filters)
- Extending an EXISTING repository or modifying an existing feature
- Reactive repositories, auth flows, streaming
- REST projects (dio/retrofit) — Supabase only for now

Requirements half-in, half-out? Scaffold the in-scope part with the spec, then implement the rest via the routed pattern skills on top of the stamped files.

## Workflow

**1. Write the spec** to `specs/<feature>.json` — in ONE go, no exploration needed beyond the requirements:

```json
{
  "feature": "announcements",
  "pages": ["list", "detail"],
  "model": {
    "name": "announcement",
    "fields": [
      { "name": "id",          "type": "String",    "column": "id" },
      { "name": "title",       "type": "String",    "column": "title" },
      { "name": "body",        "type": "String",    "column": "body" },
      { "name": "publishedAt", "type": "DateTime?", "column": "published_at" }
    ]
  },
  "repository": "create",
  "operations": [
    { "name": "getAnnouncements", "kind": "list",
      "source": { "table": "announcements",
                  "order": { "column": "published_at", "desc": true } } },
    { "name": "getAnnouncementById", "kind": "single",
      "source": { "table": "announcements", "byId": true } }
  ],
  "errors": []
}
```

Schema rules:
- `feature`: snake_case, plural. `pages`: `["list"]` or `["list", "detail"]`.
- `model.name`: snake_case singular. `model.fields`: `name` camelCase, `type` one of `String int double bool DateTime` (append `?` for nullable), `column` the backend column (omit if identical to name). An `id` field of type `String` is required.
- `repository`: always `"create"` (extending existing = out of scope).
- `operations`: exactly one `"kind": "list"`; exactly one `"kind": "single"` with `"byId": true` iff `pages` includes `detail`. `source.order` is optional, list-only. Any number of mutations: `{ "name": "deleteAnnouncement", "kind": "delete", "source": { "table": ..., "byId": true }, "confirm": true }` or `{ "name": "markRead", "kind": "action", "source": { "table": ..., "byId": true, "set": { "read_at": "now" } } }` — `set` values are `"now"` or literals; anything needing user input is a form, not an action.
- `errors`: extra failure classes beyond the generated LoadFailure — `{ "class": "<Feature><Case>Failure", "code": "snake_case" }`. Usually empty for read-only features.

**2. Run the generator** (from the repo root):

```
dart run <this skill's directory>/scaffold_feature.dart specs/<feature>.json
```

The scripts live in this pattern's OWN directory — wherever this PATTERN.md sits. Use that path; the generator's report prints exact resolved paths for every later command.

Invalid spec → it prints ALL problems at once; fix the spec, re-run. Valid spec → it stamps everything and prints **TASKS** — the complete list of what remains, with file:line references.

**3. Complete every task, in order.** Typically: design the list tile and detail layout (tokens only), fill `specs/<feature>.i18n.json` in one Write and run the apply script (never edit `.arb` files by hand), wire the entry point with the snippet the report gives you. Codegen (build_runner, part directives, gen-l10n) is **already run by the generator** — re-run build_runner only if you add new annotated classes. The report's REQUIREMENTS-ALREADY-SATISFIED section maps cross-cutting requirements (offline, pull-to-refresh, states, deep links) to their stamped mechanism — consult it instead of verifying by grep. Anything beyond the stamp: normal pattern skills (`/cubit-creation`, `/network-creation-supabase`, `/ui`, ...).

**4. Gate — one command, fix any FAIL, re-run until PASS:**

```
dart run <this skill's directory>/verify_feature.dart
```

It runs gen-l10n, conditional build_runner, analyze (in-scope vs pre-existing classified for you — errors fail anywhere, but pre-existing warnings and infos in untouched files are NOT yours), tests (failures-only output), the TODO(ai) sweep, the project checkers, and ARB parity, and prints one compact PASS/FAIL block. Never run these checks individually.

## Rules

- **Trust the stamp — do not re-verify it.** The generator's report shows every insertion it made (routes, GoRoutes, ARB keys) verbatim, and its **PROJECT FACTS** section lists the theme token roles, text styles, colors, shared ARB keys, and reuse inventory extracted from the repo *at stamp time* (same content as the `/project-facts` skill). Use those directly — never grep or re-read files to rediscover them. The full report is saved at `specs/<feature>.tasks.md`; re-read it from there if it scrolls out.
- **Batch your reads AND your edits.** Issue all Read calls for files you plan to edit in ONE message; likewise issue every independent Edit in ONE message — both pages, their imports, and any other unrelated files together. An edit that needs a new import carries the import edit in the same message. One file per turn is the failure mode.
- **Hoist nullable fields before null-checks.** When designing the tile/detail layout, write `final publishedAt = item.publishedAt;` style locals before `if (x != null)` — field access does not type-promote in Dart.
- **Do NOT restructure stamped files.** They ARE the convention — wide seam, one-shot error field, double-fire guards, `isClosed` checks, theme tokens, Semantics identifiers, fake-cubit widgetbook seams are already correct.
- The spec is the single source for names/fields/queries — if a requirement changes them, change the spec and re-run with `--force` *before* hand-editing stamped files.
- If the generator prints a `WARNING:`, do that step manually before the gate.
- Keep the spec file committed — it documents the feature's contract.
