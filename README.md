# flutter-skill

All Flutter conventions, rules, and pattern skills in one repo, registered at user level.

**How it routes:** only the `flutter-skill` router carries a real description (auto-triggers on Flutter coding tasks). Pattern skills under `skills/` are registered too — so they're invocable with the Skill tool — but their descriptions are deliberate stubs, so they never fire on their own. The router's routing table is the single authority for when to invoke each pattern.

## Layout

```
flutter-skill/
├── .claude-plugin/plugin.json  # the `flutter` plugin manifest (no version: installs follow commits)
├── SKILL.md      # router: working principles, core rules (architecture/coding/UI), pattern routing table
├── skills/       # migrated pattern skills (stub descriptions; routed by SKILL.md)
│                 #   + flutter-skill/SKILL.md, the router itself (the root SKILL.md links to it)
│                 #   + user-run commands: design-style, design-codify, flutter-skill-migrate
├── _legacy/      # not authoritative:
│   ├── skills/     #   migration queue — pre-revamp patterns not yet revamped
│   ├── migrated/   #   pre-revamp snapshots of patterns that shipped to skills/
│   └── retired/    #   patterns killed or merged away (refresh-bus, page/widget-creation)
└── setup.sh      # symlinks router + patterns into ~/.claude/skills (idempotent, rerun after adding a pattern)
```

## Setup

**As a plugin (recommended):** the kit is the `flutter` plugin in the happyface marketplace. Plugin skills are namespaced: the router is `flutter:flutter-skill`, a pattern is `flutter:cubit-creation`.

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
2. Replace its description with the stub: `Internal flutter-skill pattern — invoked via the flutter-skill router, not from this description. (<3-word hint>)`
3. Land the revamp at `skills/<name>/`; move the pre-revamp original to `_legacy/migrated/<name>/`.
4. Add its row to the router's routing table, rerun `setup.sh`.
