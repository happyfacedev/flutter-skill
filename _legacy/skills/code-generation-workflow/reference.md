# Code Generation Workflow — Reference

The dev-dependency stack, `build.yaml` configuration, and how `fix_part_directives.dart` actually rewrites part paths.

## Dev-dependencies driving generators

From `pubspec.yaml`:

| Package | Version | Drives |
|---|---|---|
| `build_runner` | `^2.10.4` | The orchestrator — invoked via `dart run build_runner build` |
| `freezed` | `^3.2.3` | `*.freezed.dart` output for `@freezed` / `@unfreezed` |
| `freezed_annotation` | `^3.1.0` | The annotations themselves (runtime + dev) |
| `json_serializable` | `^6.11.2` | `*.g.dart` output for `fromJson` / `toJson` factories |
| `injectable_generator` | `^2.9.1` | `injection.config.dart` for `@injectable` / `@singleton` |
| `hive_ce_generator` | `^1.10.0` | Hive adapters for `@HiveType` |

Retrofit (`retrofit_generator`) and the project's `simple_repository_generator` also wire into `build_runner` — search `pubspec.yaml` for the current versions.

## `build.yaml` — what it does

```yaml
targets:
  $default:
    builders:
      source_gen|combining_builder:
        options:
          build_extensions:
            '^lib/{{}}.dart': 'lib/core/generated/{{}}.g.dart'
      freezed:
        options:
          build_extensions:
            '^lib/{{}}.dart': 'lib/core/generated/{{}}.freezed.dart'
          map: false
          when:
            when: false
            maybe_when: false
            when_or_null: false
      repository_generator|repository_generator:
        generate_for:
          - lib/**.dart
      bdd_widget_test|featureBuilder:
        options:
          stepFolderName: step
        generate_for:
          - test/**
          - integration_test/**
```

Key facts:

1. **`build_extensions`** lines redirect generator output. Without these, `*.freezed.dart` and `*.g.dart` would land next to source. With them, they land in a parallel `lib/core/generated/` tree.

2. **`map: false`, `when: false`, etc.** — Freezed code-gen omits the union helpers (`map`, `maybeMap`, `when`, …) for `@freezed` classes. The project uses Dart's pattern-matching `switch` expressions instead, which work directly on sealed unions without needing the helpers. Less generated code, smaller compile.

3. **`repository_generator`** runs across `lib/**.dart` and produces the `@Generate(apiClient:)` mixin output.

4. **`bdd_widget_test`** generates `*.feature` step files for widget tests written in Gherkin — out of scope for this skill (and rarely used).

## How `fix_part_directives.dart` works

Source: `tools/fix_part_directives.dart`.

Walks `lib/` recursively. For each `.dart` file:

1. Detects `part 'foo.g.dart';` and `part 'foo.freezed.dart';` directives via regex.
2. If neither match, skips (no work to do).
3. Removes both directive forms wherever they appear in the file.
4. Computes the correct relative path from the source file's directory to its companion under `lib/core/generated/`:
   - Given source at `lib/features/x/y/foo.dart`
   - Expected `*.g.dart` at `lib/core/generated/features/x/y/foo.g.dart`
   - Relative path inserted: `../../../core/generated/features/x/y/foo.g.dart`
5. Re-inserts the directives after the last `import` / `library` / `part` line in the file (preserving header position).
6. Writes the file back.

The script is idempotent — running it on already-correct files is a no-op (the regex still removes and re-inserts, but the content ends up identical).

### When the script does NOT help

- The directive points to `.config.dart` (different naming) — that's a manual edit, not what this script handles
- The generated companion is in a non-standard location (build.yaml overridden per-target) — out of scope
- The source file lives outside `lib/` — the script only walks `lib/`

## Source-path → generated-path mapping

| Source | Generated `.freezed.dart` | Generated `.g.dart` |
|---|---|---|
| `lib/features/x/logic/models/responses/foo.dart` | `lib/core/generated/features/x/logic/models/responses/foo.freezed.dart` | `lib/core/generated/features/x/logic/models/responses/foo.g.dart` |
| `lib/features/x/logic/apis/x_api.dart` | (none — Retrofit doesn't use Freezed) | `lib/core/generated/features/x/logic/apis/x_api.g.dart` |
| `lib/features/x/logic/repositories/x_repository.dart` (with `@Generate`) | (none) | `lib/core/generated/features/x/logic/repositories/x_repository.g.dart` |
| `lib/core/injection/injection.dart` | (none) | `lib/core/injection/injection.config.dart` (**not** under `core/generated/` — this is the one exception, configured by `injectable_generator`) |

## The two-command rhythm

The most common workflow loop while iterating on models/cubits:

```bash
# Make a change to an annotated source file (add a field, add @JsonKey, etc.)

dart run build_runner build --delete-conflicting-outputs

# Test, iterate, repeat.
```

When the change includes a **new file**:

```bash
# Create the file via mason or by hand.

dart tools/fix_part_directives.dart
dart run build_runner build --delete-conflicting-outputs
```

When the cache gets confused:

```bash
dart run build_runner clean
dart run build_runner build --delete-conflicting-outputs
```

When *everything* is wrong:

```bash
rm -rf lib/core/generated
dart run build_runner build --delete-conflicting-outputs
dart tools/fix_part_directives.dart    # if any part directives broke during the nuke
```

## Watching mode (development)

`dart run build_runner watch --delete-conflicting-outputs` — useful during active model editing, regenerates on save. Trade-off: leaves a background process holding the cache lock. Stop the watch (`Ctrl+C`) before running `clean` or `nuke` recoveries.

## Mason brick

The only registered brick is `simple_freezed_model` (version `^1.0.0+1` per `mason.yaml`). Invocation:

```bash
mason make simple_freezed_model \
  --name <ClassName> \
  --output-dir <directory>
```

`--name` accepts the PascalCase class name; the brick produces a snake_case filename automatically.

There's no separate brick for cubits / repositories / APIs in this project — those are written by hand following the patterns in `/cubit-creation` / `/network-creation` / `/network-creation-supabase`.

## Common error → fix

| Error | Likely cause | Fix |
|---|---|---|
| "Conflicting outputs were detected" | Stale generated file from before a refactor | `--delete-conflicting-outputs` flag (you forgot it) or `build_runner clean` then re-run |
| "Target of URI doesn't exist: 'foo.freezed.dart'" | Part directive points to a sibling but file is under `core/generated/` | `dart tools/fix_part_directives.dart` |
| "Type 'Foo' not found" in a file using `_$Foo` | Generated file doesn't exist yet | `build_runner build` |
| "The class 'X' has no instance method 'copyWith'" | Freezed file is stale | `build_runner build --delete-conflicting-outputs` |
| "GetIt: Object/factory with type X is not registered" | DI config didn't pick up the new annotation | `build_runner build --delete-conflicting-outputs` (and verify the annotation is correct) |
| "fromJson is not defined" for a model | `@JsonSerializable` missing or `.g.dart` not generated | Add the annotation if missing, then `build_runner build` |
| Build silently produces nothing | Generator failed quietly | Check stdout for warnings; try `build_runner clean` |
