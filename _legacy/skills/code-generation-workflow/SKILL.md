---
name: code-generation-workflow
description: The build_runner + mason brick + fix_part_directives workflow for this project. Covers when to run `dart run build_runner build --delete-conflicting-outputs` (after adding `@freezed` / `@injectable` / `@singleton` / `@JsonKey` / `@Generate` / `@HiveType` / `@RestApi` annotations), when to run `dart tools/fix_part_directives.dart` (after `mason make simple_freezed_model` or after any new Freezed/JsonSerializable file is created — fixes `part 'x.g.dart'` paths because build.yaml redirects outputs to `lib/core/generated/`), the mason brick command (`mason make simple_freezed_model --name X --output-dir <dir>`), what each generator produces (`*.freezed.dart`, `*.g.dart`, `injection.config.dart`), how to recover from "conflicting outputs" errors (delete `lib/core/generated/` and rerun), and which dependency triggers which generator. Use after any model / cubit / repository change touching code-gen annotations, after creating a new model via mason, when build_runner emits errors, when generated files are missing or stale, or when the user mentions "build_runner", "build runner", "freezed", "fix part directives", "mason", "code gen", "code generation", "generated file", "injection.config.dart", ".g.dart", ".freezed.dart", "conflicting outputs", or "delete conflicting outputs". The model shape itself → /model-creation. The cubit shape → /cubit-creation. The DI annotation choice → /bootstrap-composition-root.
argument-hint: "[command]"
---

# Code Generation Workflow

This project uses **`build_runner`** to drive multiple generators that produce companion files (`*.freezed.dart`, `*.g.dart`, `injection.config.dart`) alongside annotated source. The `build.yaml` redirects generator output to `lib/core/generated/` instead of leaving artifacts next to source — which means part directives in source files must point to that subtree, not to a sibling file. The `fix_part_directives.dart` script keeps those `part` lines correct.

Most of the time the workflow is two commands:

```bash
dart run build_runner build --delete-conflicting-outputs
dart tools/fix_part_directives.dart
```

The skill covers when to run each, what each fixes, when mason fits in, and how to recover from a broken state.

## Critical Rules (Never Break)

1. **ALWAYS pass `--delete-conflicting-outputs`** when running `build_runner build`. *Why:* the generator refuses to overwrite a previously-generated file if its hash differs from what the build cache expects. The flag tells it "yes, replace stale outputs." Without it, the first run after any non-trivial refactor fails with "conflicting outputs" and forces you to delete files by hand.

2. **ALWAYS run `dart tools/fix_part_directives.dart` after creating a new Freezed/JsonSerializable file** (either by hand or via `mason make simple_freezed_model`). *Why:* the mason brick scaffolds a model file with `part 'foo.freezed.dart';` and `part 'foo.g.dart';` pointing to siblings, but `build.yaml` redirects generator output to `lib/core/generated/` — so the source's `part` lines need to point there instead. The script rewrites those `part` paths to the correct relative location under `core/generated/`. Without it, the build fails with "target of URI doesn't exist."

3. **Re-run `build_runner` after ANY change to an annotation that drives generation.** *Why:* adding `@freezed`, `@injectable`, `@singleton`, `@JsonKey`, `@Generate`, `@RestApi`, `@HiveType`, `@PostConstruct`, or any sibling annotation invalidates the generated file. Continuing without re-running produces stale generated code that compiles but behaves wrong — wrong DI registration, missing `fromJson`, missing `copyWith` fields, etc.

4. **NEVER edit a generated file directly.** *Why:* `injection.config.dart`, `*.freezed.dart`, `*.g.dart` are all regenerated from scratch on every build. Edits are silently lost on the next `build_runner` run. If you need to change the output, change the *annotation* or the source class.

5. **Generated files live under `lib/core/generated/` — never commit changes to other locations.** *Why:* the project's `build.yaml` explicitly redirects output to that tree. If you see `*.freezed.dart` or `*.g.dart` files appearing next to source, the part directives weren't fixed (`fix_part_directives.dart` step was skipped) or `build.yaml` was modified — either way, fix the cause before committing.

## Decision: which command, when

### After adding a Freezed model OR a `@JsonKey` annotation OR a `fromJson` factory

```bash
dart run build_runner build --delete-conflicting-outputs
```

Produces `lib/core/generated/<feature>/logic/models/.../<name>.freezed.dart` (the union / copyWith) and `<name>.g.dart` (the `fromJson` / `toJson`).

**If you just created the file** (it's new in this run, not just edited):

```bash
dart tools/fix_part_directives.dart
```

Then re-run `build_runner`. The script only matters for *new* files — once part directives are correct, editing an existing model doesn't invalidate them.

### After adding `@injectable`, `@singleton`, `@lazySingleton`, `@singletonAsync`, or `@Environment`

```bash
dart run build_runner build --delete-conflicting-outputs
```

Produces `lib/core/injection/injection.config.dart`. No part-directive fix needed — `injection.config.dart` is its own file in its canonical location, not a `part of` companion.

### After adding `@Generate(apiClient: FooApi)` mixin to a repository

```bash
dart run build_runner build --delete-conflicting-outputs
```

Produces the generated repository mixin under `lib/core/generated/` matching the source path. No part-directive fix needed.

### After adding `@RestApi` (Retrofit) on a new API class

```bash
dart run build_runner build --delete-conflicting-outputs
```

Produces `_FooApi` implementation under `lib/core/generated/`. No part-directive fix needed (the source already does `part '_foo_api.g.dart';` correctly because the mason brick handles it, but if you wrote it by hand, the part directive needs to point to the `core/generated/` path — same script applies).

### After adding `@HiveType` / `@HiveField` on a model

```bash
dart run build_runner build --delete-conflicting-outputs
```

Produces the Hive adapter. Add the model + adapter to `hive_registrar.g.dart` regeneration via the same command.

### Creating a new model via mason

```bash
mason make simple_freezed_model --name <name> --output-dir lib/features/<feature>/logic/models/<responses|request_bodies>/
dart tools/fix_part_directives.dart
dart run build_runner build --delete-conflicting-outputs
```

Three commands in this order. The mason brick scaffolds the model file with placeholder part directives; the fix script rewrites them; `build_runner` then succeeds.

## Recovery: "conflicting outputs"

If `build_runner build` fails despite the `--delete-conflicting-outputs` flag, the cache is in a state the generator can't resolve. Two escalation steps:

```bash
# Step 1: Clean rebuild
dart run build_runner clean
dart run build_runner build --delete-conflicting-outputs

# Step 2: Nuke the generated tree (if step 1 didn't help)
rm -rf lib/core/generated
dart run build_runner build --delete-conflicting-outputs
dart tools/fix_part_directives.dart   # if any part directives broke
```

Step 2 is safe — everything under `lib/core/generated/` is regenerated from source. Step 1 is preferred because it doesn't force a full rebuild from scratch (faster).

## Recovery: "target of URI doesn't exist" on a part directive

Your source file says `part 'name.freezed.dart';` but the actual generated file is at `lib/core/generated/.../name.freezed.dart`. The part directive needs to point there with a relative path.

```bash
dart tools/fix_part_directives.dart
```

The script walks `lib/`, finds every file with `.g.dart` / `.freezed.dart` part directives, removes them, and re-inserts the correct relative paths to `lib/core/generated/`. Safe to run repeatedly — idempotent on already-correct files.

## Generator-by-annotation map

| Annotation | Generator | Output file | Notes |
|---|---|---|---|
| `@freezed`, `@unfreezed`, `@Freezed(...)` | `freezed` | `*.freezed.dart` (under `lib/core/generated/`) | The copyWith, equality, sealed-union machinery |
| `@JsonSerializable`, `@JsonKey`, factory `Foo.fromJson` | `json_serializable` | `*.g.dart` (under `lib/core/generated/`) | The `_$FooFromJson` / `_$FooToJson` |
| `@injectable`, `@singleton`, `@lazySingleton`, `@singletonAsync`, `@PostConstruct`, `@Environment` | `injectable_generator` | `lib/core/injection/injection.config.dart` | Aggregate registration file |
| `@RestApi`, `@GET`, `@POST`, `@Path`, `@Body`, etc. | `retrofit_generator` | `*.g.dart` (under `lib/core/generated/`) | Retrofit implementation class |
| `@Generate(apiClient: FooApi)` | `simple_repository_generator` | `*.g.dart` (under `lib/core/generated/`) | Repository mixin wrapping API calls in `Either<Failure, T>` |
| `@HiveType`, `@HiveField` | `hive_ce_generator` | `*.g.dart` adapter under `lib/core/generated/` + `hive_registrar.g.dart` | Hive adapters for persisted models |

Every generator above is wired through `build_runner` — there's one orchestrator and one command to run.

## Mason brick — `simple_freezed_model`

The only brick registered in `mason.yaml`. It scaffolds a Freezed model with:
- The `@freezed` annotation
- A class with a single `const factory` constructor (the `factoryName` defaults to the class name with appropriate casing)
- `fromJson` factory wired up
- `part 'name.freezed.dart';` and `part 'name.g.dart';` directives (which the fix script then redirects to `core/generated/`)

```bash
mason make simple_freezed_model \
  --name ItemResponse \
  --output-dir lib/features/organization/logic/models/responses/
```

The output filename is derived from `--name` (snake_case): `item_response.dart`.

**After running mason, ALWAYS:**
1. `dart tools/fix_part_directives.dart` — fix the placeholder part directives
2. `dart run build_runner build --delete-conflicting-outputs` — generate the companions

Without step 1, step 2 will fail. Without step 2, the model has no `copyWith` / `fromJson`.

## Recurring "what command should I run?" table

| You just did | Run |
|---|---|
| Edited an existing Freezed model (added a field) | `build_runner` only |
| Edited an existing model's `@JsonKey` mapping | `build_runner` only |
| Created a new Freezed model file (any way) | `fix_part_directives` → `build_runner` |
| Created a new model via `mason make simple_freezed_model` | `fix_part_directives` → `build_runner` |
| Added `@injectable` / `@singleton` to a cubit / repo / service | `build_runner` only |
| Added `@Generate(apiClient:)` mixin to a repository | `build_runner` only |
| Edited a `@RestApi` class (new endpoint) | `build_runner` only |
| Created a new `@RestApi` class | If you wrote it by hand and used local `part 'x.g.dart';` → `fix_part_directives` → `build_runner`. If you scaffolded via mason → same as model |
| Added `@HiveType` to a model | `build_runner` only |
| Edited any non-annotated file (UI, business logic without `@*`) | Nothing — no generators care |
| Got "conflicting outputs" despite the flag | `build_runner clean` → `build_runner build --delete-conflicting-outputs` |
| Got "target of URI doesn't exist" for a `part` | `fix_part_directives` → `build_runner` |
| Generated file looks stale / from before a refactor | `build_runner clean` → `build_runner build --delete-conflicting-outputs` |
| Confused about the state of `lib/core/generated/` | `rm -rf lib/core/generated && build_runner build --delete-conflicting-outputs` |

## What this skill does NOT cover

- **What to put in the annotated class** (the model shape, the cubit shape, the repository shape) — see the matching domain skill: `/model-creation`, `/cubit-creation`, `/network-creation`, `/network-creation-supabase`, `/bootstrap-composition-root`.
- **Why the project uses code generation at all** (Freezed vs hand-rolled equality, Retrofit vs hand-rolled clients) — that's an architectural decision, not a workflow concern.
- **`flutter pub get` / dependency management** — that's pub workflow, separate from build_runner.

## Reference

See [reference.md](reference.md) for:
- The full list of code-generation dependencies in `pubspec.yaml` (which `dev_dependency` drives which generator)
- The `build.yaml` configuration that redirects outputs to `lib/core/generated/`
- How `fix_part_directives.dart` works step-by-step (so you can debug it if needed)
- The relationship between source path and generated path

## Checklist

- [ ] After any change to a code-gen annotation: `dart run build_runner build --delete-conflicting-outputs`
- [ ] After creating a new file with `part '...freezed.dart';` or `part '...g.dart';`: `dart tools/fix_part_directives.dart` BEFORE `build_runner`
- [ ] After `mason make simple_freezed_model`: fix script THEN build_runner — never skip the fix script
- [ ] On "conflicting outputs" error: `build_runner clean` then re-run with the flag
- [ ] On "target of URI doesn't exist": run the fix script
- [ ] Generated files live under `lib/core/generated/` — anything elsewhere is wrong
- [ ] Never hand-edit `injection.config.dart`, `*.freezed.dart`, or `*.g.dart` — edit the annotation/source instead
- [ ] When in doubt about cache state: `rm -rf lib/core/generated && build_runner build --delete-conflicting-outputs`
