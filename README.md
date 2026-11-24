# flutter-skill

All Flutter conventions, rules, and pattern skills in one repo, registered at user level.

**How it routes:** only the `flutter-skill` router is loaded by the agent (it auto-triggers on Flutter coding tasks). Patterns are plain files inside its folder, not registered skills, so they cost no context until the router's table sends the agent to read one. The table is the single authority for when to read each pattern.

## Layout

```
flutter-skill/
├── .claude-plugin/plugin.json  # the `flutter` plugin manifest (no version: installs follow commits)
├── skills/
│   ├── flutter-skill/
│   │   ├── SKILL.md    # router: working principles, core rules (architecture/coding/UI), pattern routing table
│   │   └── patterns/   # <name>/PATTERN.md + its templates and references
│   └── design-style, design-codify, flutter-skill-migrate   # user-run commands
├── _legacy/      # not authoritative:
│   ├── skills/     #   migration queue — pre-revamp patterns not yet revamped
│   ├── migrated/   #   pre-revamp snapshots of patterns that shipped
│   └── retired/    #   patterns killed or merged away (refresh-bus, page/widget-creation)
└── setup.sh      # symlinks skills/* into ~/.claude/skills (idempotent)
```

## Setup

**As a plugin (recommended):** the kit is the `flutter` plugin in the happyface marketplace. Plugin skills are namespaced: the router is `flutter:flutter-skill`.

```text
/plugin marketplace add happyfacedev/happyface-plugins
/plugin install flutter@happyface
```

Then turn on auto-update once under `/plugin` > Marketplaces > happyface, so every push to this repo reaches you at the next session start. The plugin is a cached copy: to work on the kit itself, add your local happyface-plugins checkout as the marketplace instead, or keep using `setup.sh`, which reads this checkout in place. Don't use both at once, or every skill is registered twice.

**From this checkout:**

```bash
./setup.sh
```

Recommended per Flutter project: one line in `CLAUDE.md` — "Flutter project — invoke `flutter-skill` before planning or writing any code." — to make loading deterministic instead of description-triggered.

**Adopting in a project that has its own project-level skills/rules:** run `/flutter-skill-migrate` inside that project. It inventories `.claude/skills/`, `.claude/commands/`, and CLAUDE.md files, retires what this kit supersedes, keeps genuine project facts/skills, and wires the CLAUDE.md invoke line — with a user-approved plan before anything is deleted.

## Migrating a pattern (from `_legacy/skills/`)

1. Revamp body: why-framed critical rules, checklist, <500 lines; templates/reference only as needed.
2. Remove its frontmatter and name the file `PATTERN.md`.
3. Land the revamp at `skills/flutter-skill/patterns/<name>/`; move the pre-revamp original to `_legacy/migrated/<name>/`.
4. Add its row to the router's routing table.
