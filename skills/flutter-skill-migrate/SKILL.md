---
name: flutter-skill-migrate
description: Manual command — run ONLY when the user explicitly invokes /flutter-skill-migrate. Never auto-trigger. (One-time migration of a project off legacy project-level skills/rules onto the user-level flutter-skill kit.)
disable-model-invocation: true
---

# flutter-skill-migrate — adopt the user-level kit

Run inside a Flutter project that still carries its own project-level Claude guidance (`.claude/skills/`, `.claude/commands/`, a rule-heavy `CLAUDE.md`). The flutter-skill kit is the single source of truth for Flutter conventions; this command removes what the kit supersedes, keeps what is genuinely project-specific, and wires the project's `CLAUDE.md` to load the kit deterministically.

The end state is a **smaller** project footprint: `CLAUDE.md` comes out shorter than it went in, holding only project facts plus the invoke line. If the migration makes it longer, generic rules are leaking back in.

## Phase 0 — Preflight (stop if any fails)

- `pubspec.yaml` exists at the project root — otherwise this is not a Flutter project; stop.
- The kit router is available: the `flutter-skill` skill, either through the `flutter@happyface` plugin (`flutter:flutter-skill`) or through `setup.sh` (`~/.claude/skills/flutter-skill/SKILL.md`) — otherwise the kit isn't registered; tell the user to install `flutter@happyface` or run `setup.sh` from the flutter-skill repo, then stop.
- Read the kit router (the `flutter-skill` skill) now — its core rules and routing table are the coverage map every verdict below is judged against. Read a pattern's `PATTERN.md` only when a verdict needs it (e.g. checking whether a specific project rule survives anywhere in the kit).
- `git status` is clean — deletions and the `CLAUDE.md` rewrite should land as one reviewable commit. If dirty, ask the user before proceeding.

## Phase 1 — Inventory

Enumerate every piece of project-level agent guidance:

- `.claude/skills/*/` — project skills (read frontmatter *and* body)
- `.claude/commands/**/*.md` — project slash commands
- `CLAUDE.md`, `CLAUDE.local.md`, `.claude/CLAUDE.md`, nested `**/CLAUDE.md`
- `AGENTS.md`, `.cursorrules`, `.cursor/rules/` — same duplication problem via other tools; include them
- `.claude/settings.json` / `.claude/settings.local.json` hooks that reference any of the above

Also read `pubspec.yaml` dependencies — they decide which kit variants apply (Phase 4).

## Phase 2 — Verdicts

Judge every inventory item against the kit's router and patterns:

| Verdict | It is... | Action |
|---------|----------|--------|
| **Superseded** | Same ground as a kit pattern or core rule — especially a skill sharing a kit pattern's name | Delete the skill/command; strip the CLAUDE.md section |
| **Project fact** | Package name, build/run/codegen commands, flavors, feature list, backend variant, env setup | Keep — but it lives in `CLAUDE.md`, never in a skill |
| **Project skill** | Ground the kit doesn't cover (deploy, release, domain workflows, non-Flutter tooling) | Keep as a project skill, untouched |
| **Hybrid** | Mostly superseded, but carrying project-specific deltas | Extract the delta into `CLAUDE.md`, then delete the rest |
| **Conflict** | Contradicts a kit rule (e.g. mandates SharedPreferences, relative imports, cubit-to-cubit calls) | Never resolve silently — Phase 3 puts it to the user |

### Critical Rules (Never Break)

1. **A project skill sharing a kit pattern's name is the highest-priority removal.** Kit patterns are files the router reads, not registered skills, so nothing shadows the local copy: it stays live, and an agent following `/cubit-creation` can load the stale one instead of the kit's. If the local copy differs on purpose, the difference is either a project fact (extract it) or kit feedback (Rule 4) — never a reason to keep the copy.

2. **Judge content, not filenames.** A skill named `deployment` may embed cubit conventions; a `CLAUDE.md` "architecture" section may be half build commands. Verdicts attach to *rules*, and one file can receive several verdicts.

3. **Never copy kit rules into the project — in either direction.** Don't preserve a deleted skill by pasting its rules into `CLAUDE.md`, and don't restate kit rules there "for visibility." A restated copy drifts stale the day the kit improves, and from then on it contradicts the source it was copied from.

4. **A project rule that's *better* than the kit's is kit feedback, not a keeper.** When a local convention genuinely improves on the kit, list it in the final report as a proposed kit change (the kit repo is happyfacedev/flutter-skill). Keeping it locally forks the conventions.

## Phase 3 — Present the plan, wait for approval

Before touching anything, show the user:

1. The verdict table — every item, its verdict, a one-line reason.
2. Each conflict as an explicit question: kit rule vs project rule — which wins?
3. A sketch of the resulting `CLAUDE.md` (shape below).

**Do not delete or edit anything until the user approves.** Everything is git-recoverable, but the plan is where a mis-verdict gets caught cheaply.

## Phase 4 — Apply

Delete the superseded skills/commands, apply the hybrid extractions, and rewrite `CLAUDE.md` to this shape:

```markdown
# <Project>

Flutter project — ALWAYS invoke the `flutter-skill` skill before planning or writing ANY code, even for small changes.

## Project facts

- Package: `<name>` — imports are `package:<name>/...`
- Backend: REST (dio + retrofit) → `/network-creation` | Supabase → `/network-creation-supabase` + `/auth-flow-supabase`  ← pick from pubspec
- Build / codegen: <commands>
- <flavors, feature list, structure quirks — only what the kit's router calls project facts>

## <Kept project-specific sections, verbatim>
```

- The invoke line sits at the top, phrased as an instruction — it makes kit loading deterministic instead of description-triggered.
- Recording the backend variant is mandatory: the router's table routes on it.

## Phase 5 — Verify & report

- [ ] No name collisions remain: nothing in `.claude/skills/` shares a name with a kit skill or a pattern in the router's table
- [ ] Grep the project for references to deleted skills/commands (remaining skills, `settings.json` hooks, docs, plan files) — fix or remove each
- [ ] `CLAUDE.md` is shorter than before and contains no rule the kit already carries
- [ ] Report: removed / kept / extracted lists, conflict resolutions, proposed kit changes (Rule 4)
- [ ] Remind the user to review `git diff` and commit — never commit unasked
