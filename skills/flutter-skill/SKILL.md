---
name: flutter-skill
description: Flutter development conventions, rules, and pattern routing. ALWAYS invoke this before planning or writing ANY code in a Flutter project (any repo with a pubspec.yaml), even for small changes. Not for non-Flutter projects.
---

# flutter-skill — Flutter conventions & core rules

Project-specific facts (package name, directory structure, feature list, build commands, which variants apply) live in each project's CLAUDE.md.

## Working principles

- **Scope discipline.** Modify only the scope requested — not global getters, shared utilities, or other flows. When a change touches shared code, confirm the blast radius before editing.
- **Simplicity first.** Prefer the simplest solution that follows the conventions in this skill and its patterns; no clever workarounds or extra abstractions when a straightforward approach exists.
- **Step-by-step compliance.** When asked to work one-by-one, do exactly that: complete each step, pause for confirmation, never batch ahead.
- **Rules and patterns first — project files as fallback.** Resolve tasks from this file's rules, the routed patterns, and context already in the conversation. Only if information required to complete the task is still missing — an integration point, an existing symbol or widget to reuse, a convention nothing here covers — Read/Search the specific project files that fill that gap. Keep fallback reads purposeful — a direct Read of a known path beats a Grep sweep, and don't scan the project up front by default — but when completing the task genuinely requires understanding an unfamiliar area, explore it.
- **Rules outrank neighboring code.** When a rule or pattern prescribes a convention and nearby files do it differently, follow the rule — legacy files usually predate it, and matching them keeps the codebase from ever converging.
- **Reuse before creating.** Before writing any new button, field, dialog, or common UI element, check the project's existing inventory — reinventing an existing widget is the most common kind of drift. If the project provides a `/project-facts` skill, invoke it first: it injects the live design-token roles and the full reuse inventory (widget/util signatures with docs), replacing every token or inventory grep. Otherwise `/ui` covers where to look.
- **Plans must carry their rules.** Rules and patterns are matched against user requests, not plan steps — an agent executing a plan never re-routes. Every plan step that creates a component must embed "→ Invoke /pattern-name (flutter-skill) before writing code" and surface that pattern's critical rules. Writing the plan itself → `/planning`.
- **Read files just before editing them, not up front.** Sequence: read rules/patterns → write new files → read integration files → edit them. Early reads go stale by the time you edit, causing failed edits and re-reads.
- **Don't re-read what you already have.** Read a pattern's PATTERN.md once per session; read only the templates for components you will actually create; don't re-read a file whose content hasn't changed since your last read.

## Core rules

### Architecture

- **DI**: constructor injection everywhere; `getIt` may only be called in the composition root (`bootstrapper` / `shared_main`) or inside a `BlocProvider`/`RepositoryProvider`/`pageBuilder` `create:` callback. Lifetimes: cubits are `@injectable` (fresh per page unless app-lifetime — see `/cubit-creation`); API clients and repositories are `@lazySingleton`. `@singleton` cubits and `BlocProvider.value` outside the composition root or tests need explicit user approval — app-lifetime state has wide blast radius, `.value` aliases an externally-owned instance and leaks lifecycle ownership. Registration always goes through the injectable generator — never manual (`GetIt.I.registerSingleton`, `static final` instances).
- **Repositories**: abstract class + concrete `Impl`; every data operation returns `Either<Failure, T>` (dartz) — the wide seam: transport failures (offline/timeout) pass through unchanged, never re-narrowed to a feature failure base (mechanics → the network patterns); `@lazySingleton` (stateless transport adapters — no reason to re-instantiate). When data is shared across cubits/pages, the repository becomes reactive (BehaviorSubject cache + `watchX()` streams) → `/reactive-repository`. Transport mechanics → `/network-creation` or `/network-creation-supabase` per the routing table.
- **Cubits**: never depend on or call another cubit — coordinate via a parent widget `BlocListener` (same page) or a reactive repository stream (`/reactive-repository`, cross-page). Everything else — creation, state shape, `copyWith` conventions, error reporting, `HydratedCubit` persistence — lives in `/cubit-creation`.
- **Widgets**: `StatelessWidget` by default; `StatefulWidget` only to own a controller (`TextEditingController`, `AnimationController`, …), isolated to the smallest widget that needs it. No logic in `build` — initialization goes in `BlocProvider`'s `create:` callback. Page structure, section extraction, placement, design-system usage → `/ui`.
- **Errors**: expected business failures are `Failure` values flowing through `Either` — never thrown. Reporting and display mechanics → `/cubit-creation`.
- **Navigation**: GoRouter; routes go through the `AppRoutes` enum, never bare path strings at call sites. `go` replaces the stack, `push` adds to it — ask the user when the right one is unclear. Route wiring, guards, page types, shell-vs-fullscreen → `/navigation-gorouter`.
- **Persistence**: state that must survive restarts persists through the state layer (mechanics → `/cubit-creation`); ad-hoc key-value storage via Hive — never SharedPreferences — only for simple values outside cubit state.
- **Feature isolation**: a file under `lib/features/X/` never imports from `lib/features/Y/` — shared models, state, or signals route through `lib/core/`. A feature's `logic/` piece is *promoted* to `lib/core/<domain>/` when it is an app-lifetime singleton in the global Bootstrapper OR two-plus other features need its models/repository; migrate the smallest self-contained piece (the UI half stays in the feature), and when touching a file that already violates the rule, fix that import as part of the change — never extend a violation.
- **Standard layout**: `lib/core/<concern>/` is the platform tier (auth, organization, network, failures, services, navigation, startup, theme, widgets, utils, localization, router, injection, generated); `lib/features/<feature>/` is the feature tier — `logic/` (apis, repositories, models, cubit) + `ui/` (pages, widgets). Feature folder names are snake_case: **plural** when the user has many of the thing (`notifications`, `documents`), **singular** for single-instance flows or non-countable areas (`auth`, `home`, `onboarding`) — "does the user have N of these?" decides.
- **File shape**: one class per file (tiny, tightly-coupled helpers excepted); split files past ~300 lines and methods past ~25.

### Coding standards

- Package imports (`package:<app>/...`), never relative.
- Never force-unwrap (`!`) a nullable value — check for `null` and handle that path explicitly (typed failure, early return, or sensible default). `!` turns a representable state into an uncatchable runtime crash.
- New dependencies: check pub.dev for the latest version, pin with caret (`^x.y.z`) — never `any` or open ranges.
- Every user-facing string is localized: `context.localization.<key>`, added to **all** `.arb` files under `lib/core/localization/arb/`, following the existing key naming. No hardcoded UI strings.
- `const` constructors wherever possible.

### UI standards

- **Theme tokens only, via `BuildContext` extensions**: all design tokens are read off the context — `context.colors`, `context.styles`, `context.spacing`, `context.radius`, `context.iconSize`, `context.motion` (see the project's `lib/core/theme/extensions.dart`). No literal colors, inline `TextStyle()`, magic-number spacing, or static token classes — literals and statics bypass light/dark theming and can't be updated centrally. Carve-out: static `AppColors.*` constants on surfaces that intentionally render identically in both themes.
- **Semantics identifiers on every interactable**: anything with `onTap`/`onPressed`/`onChanged`/`onSubmitted` gets `Semantics(identifier: '<feature>-<element>[-<qualifier>]')` — kebab-case, never localized. Without it the node is invisible to Maestro E2E; identifiers are stable contracts, renaming one breaks existing flows. Skip purely decorative widgets and anything covered by a parent `Semantics` at the right granularity.
- **No `Widget _buildX()` builder methods** — extract separate `StatelessWidget` classes: builder methods can't be `const`, can't rebuild independently, and are invisible to the inspector and Maestro. Private `_FooSection` in the same file for one-off sections; promote to `ui/widgets/` when reused.

## Patterns

Patterns are files, not skills: `/<pattern>` anywhere in this kit (and "invoke `/<pattern>`" in a plan) means **read `patterns/<pattern>/PATTERN.md` in the directory that holds this file, then follow it**. Don't call the Skill tool with a pattern name — a same-named project skill is a different thing. A pattern's own links are relative to its folder. **This table is their only routing authority**: read the matching pattern before writing code for its component type.

| Task involves... | Read first |
|------------------|--------------|
| Planning, scoping, or breaking down a multi-layer change | `/planning` |
| NEW standard feature — list (+ detail) from one Supabase table or RPC, optional delete/fixed-value actions | `/feature-scaffold` — check its CAN table first; doesn't fit → the normal patterns below |
| Cubit, state, BlocProvider, error reporting, restart-surviving state | `/cubit-creation` |
| Data model (Freezed, JSON, fromJson) | `/model-creation` |
| Failure classes, error-code mapping, failure ARB keys | `/failure-modeling` |
| Data shared across cubits/pages, "tell another cubit to update", cache + stream | `/reactive-repository` |
| REST API client, repository, endpoint (project uses `dio` + `retrofit`) | `/network-creation` |
| Supabase repository, RPC, Postgrest, `.from()` (project uses `supabase_flutter`) | `/network-creation-supabase` |
| Auth flow — sign in/out/up, session restore, AuthCubit/AuthState, auth events, new auth operation | `/auth-flow-supabase` |
| Form (inputs, validation, form cubit, submit flow) | `/form-creation` |
| Route entry, navigation, guards, deep-link landing | `/navigation-gorouter` |
| Page, screen, widget, UI section, styling, anything visual | `/ui` |
| Unit test, bloc test, mocks/fakes, test coverage | `/unit-testing` |
| Widgetbook use case, catalog story, previewing a page/widget, coverage-gate backfill | `/widgetbook-catalog` |

**User-run commands — never auto-invoke:** `/design-style` (decide the app's complete design system in a collaborator session), `/design-codify` (convert the locked spec into theme/token/widget code), and `/flutter-skill-migrate` (one-time: retire a project's legacy project-level skills/rules that this kit supersedes and point its CLAUDE.md here). Only the user starts these; when a design gap, a missing design system, or a project still carrying project-level copies of these patterns comes up, *suggest* the matching command — don't invoke it.
