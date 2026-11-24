// Feature scaffolder v2 — spec-driven.
//
// Usage (from the repo root):
//   dart run <path-to>/scaffold_feature.dart <spec.json> [--force]
//
// The spec is a JSON file describing the feature's data contract (see the
// feature-scaffold skill for the schema and a worked example). The script:
//   1. Validates the spec HARD — all problems reported at once, nothing
//      generated on any error.
//   2. Detects the backend (supabase_flutter in pubspec => Supabase templates).
//   3. Stamps the standard files: failures, model (real fields from the spec),
//      repository (wide seam), cubit + state, pages, widgetbook use cases
//      (real sample data from the spec), tests (passing on the raw stamp),
//      and edits routes / router / all .arb files (anchored, idempotent).
//   4. Prints the TASK LIST: every remaining TODO(ai) with path:line, plus
//      the manual steps (translations, entry point, codegen, gate).
//
// Completion contract: the feature is DONE only when
//   flutter analyze && flutter test && `grep -rn "TODO(ai)" lib test` empty.

import 'dart:convert';
import 'dart:io';

// ---------------------------------------------------------------------------
// entry
// ---------------------------------------------------------------------------

void main(List<String> args) {
  final positional = args.where((a) => !a.startsWith('--')).toList();
  final force = args.contains('--force');
  if (positional.length != 1) {
    stderr.writeln(
      'Usage: dart run scaffold_feature.dart <spec.json> [--force]',
    );
    exit(64);
  }

  if (!File('pubspec.yaml').existsSync()) {
    stderr.writeln('ERROR: run from the repo root (pubspec.yaml not found).');
    exit(66);
  }
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final package = RegExp(r'^name:\s*(\S+)', multiLine: true)
      .firstMatch(pubspec)
      ?.group(1);
  if (package == null) {
    stderr.writeln('ERROR: could not read package name from pubspec.yaml.');
    exit(66);
  }
  if (!RegExp(r'^\s{2}supabase_flutter:', multiLine: true).hasMatch(pubspec)) {
    stderr.writeln(
      'ERROR: this project does not use supabase_flutter. The v1 template '
      'set is Supabase-only (validated); the REST set lands after its own '
      'bench. Implement via the normal pattern skills instead.',
    );
    exit(66);
  }

  final specFile = File(positional.first);
  if (!specFile.existsSync()) {
    stderr.writeln('ERROR: spec file not found: ${positional.first}');
    exit(66);
  }

  final Object? raw;
  try {
    raw = jsonDecode(specFile.readAsStringSync());
  } on FormatException catch (e) {
    stderr.writeln('ERROR: spec is not valid JSON: ${e.message}');
    exit(65);
  }

  final errors = <String>[];
  final spec = Spec.parse(raw, errors);
  if (errors.isNotEmpty) {
    stderr.writeln('SPEC INVALID — fix ALL of the following, then re-run:');
    for (final e in errors) {
      stderr.writeln('  - $e');
    }
    exit(65);
  }

  final n = Names(spec: spec!, package: package);
  if (Directory('lib/features/${n.f}').existsSync() && !force) {
    stderr.writeln(
      'ERROR: lib/features/${n.f} already exists. Use --force to overwrite.',
    );
    exit(65);
  }

  final created = <String>[];
  final edited = <String>[];
  final warnings = <String>[];

  void stamp(String path, String content) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    created.add(path);
  }

  stamp('lib/features/${n.f}/logic/failures/${n.f}_failure.dart', failureT(n));
  stamp(
    'lib/features/${n.f}/logic/models/responses/${n.m}_response.dart',
    modelT(n),
  );
  stamp(
    'lib/features/${n.f}/logic/repositories/${n.f}_repository.dart',
    repositoryT(n),
  );
  stamp(
    'lib/features/${n.f}/logic/repositories/${n.f}_repository_impl.dart',
    repositoryImplT(n),
  );
  stamp('lib/features/${n.f}/logic/cubit/${n.f}_state.dart', listStateT(n));
  stamp('lib/features/${n.f}/logic/cubit/${n.f}_cubit.dart', listCubitT(n));
  stamp('lib/features/${n.f}/ui/pages/${n.f}_page.dart', listPageT(n));
  if (n.hasDetail) {
    stamp(
      'lib/features/${n.f}/logic/cubit/${n.m}_detail_state.dart',
      detailStateT(n),
    );
    stamp(
      'lib/features/${n.f}/logic/cubit/${n.m}_detail_cubit.dart',
      detailCubitT(n),
    );
    stamp(
      'lib/features/${n.f}/ui/pages/${n.m}_detail_page.dart',
      detailPageT(n),
    );
  }
  stamp(
    'lib/widgetbook/use_cases/${n.f}_page_use_case.dart',
    useCaseT(n),
  );
  if (n.hasDetail) {
    stamp(
      'lib/widgetbook/use_cases/${n.m}_detail_page_use_case.dart',
      detailUseCaseT(n),
    );
  }
  stamp(
    'test/features/${n.f}/logic/cubit/${n.f}_cubit_test.dart',
    listCubitTestT(n),
  );
  if (n.hasDetail) {
    stamp(
      'test/features/${n.f}/logic/cubit/${n.m}_detail_cubit_test.dart',
      detailCubitTestT(n),
    );
  }

  final translationFiles = <String>[];
  final insertions = <String>[];
  _editRoutes(n, edited: edited, warnings: warnings, insertions: insertions);
  _editRouter(n, edited: edited, warnings: warnings, insertions: insertions);
  _editArbs(n,
      edited: edited,
      warnings: warnings,
      nonEnglish: translationFiles,
      insertions: insertions);

  // Normalize formatting of everything stamped, then persist the manifest
  // (the gate unions it with git status so scope survives dirty trees).
  Process.runSync('dart', ['format', ...created.where((f) => f.endsWith('.dart'))]);
  final manifestPath = 'specs/${n.f}.manifest.json';
  File(manifestPath).parent.createSync(recursive: true);
  File(manifestPath).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({'created': created, 'edited': edited})}\n');

  // ---- codegen — models are final per the spec, so run it here -----------
  stdout.writeln('Stamping done; running codegen (~1 min)...');
  final codegenResults = <String>[];
  var codegenFailed = false;
  void step(String exe, List<String> args, String label) {
    final r = Process.runSync(exe, args);
    if (r.exitCode == 0) {
      codegenResults.add('  DONE $label');
    } else {
      codegenFailed = true;
      final tail = (r.stderr.toString().trim().isEmpty
              ? r.stdout.toString()
              : r.stderr.toString())
          .trim()
          .split('\n')
          .reversed
          .take(5)
          .toList()
          .reversed
          .join('\n      ');
      codegenResults.add('  FAILED $label:\n      $tail');
    }
  }

  // fix_part_directives BEFORE build_runner: running it after touches source
  // mtimes past the generated outputs, making every later gate call re-run
  // build_runner (~1 min) for nothing.
  if (File('tools/fix_part_directives.dart').existsSync()) {
    step('dart', ['tools/fix_part_directives.dart'], 'fix_part_directives');
  }
  step('dart', ['run', 'build_runner', 'build', '--delete-conflicting-outputs'],
      'build_runner (freezed/injectable/widgetbook outputs)');
  step('flutter', ['gen-l10n'], 'gen-l10n (localizations)');

  // ---- report ------------------------------------------------------------
  final out = StringBuffer();
  out.writeln('Scaffolded feature "${n.f}" from ${positional.first}.\n');
  out.writeln('CODEGEN — already run by this generator, do NOT re-run it '
      'unless you add new annotated classes:');
  for (final r in codegenResults) {
    out.writeln(r);
  }
  out.writeln('  Note: blank-line churn in untouched model/generated files is '
      'a known build_runner side effect — leave it, never revert or fix it.');
  out.writeln('Created:');
  for (final f in created) {
    out.writeln('  $f');
  }
  out.writeln('Edited (the insertions below are EXACTLY what went in — '
      'trust them, do not re-open these files to verify):');
  for (final f in edited) {
    out.writeln('  $f');
  }
  for (final ins in insertions) {
    out.writeln(ins);
  }
  for (final w in warnings) {
    out.writeln('WARNING: $w');
  }

  out.writeln('\nTASKS — complete ALL, in order:');
  var i = 0;
  for (final path in created) {
    final lines = File(path).readAsLinesSync();
    for (var l = 0; l < lines.length; l++) {
      if (lines[l].contains('TODO(ai)')) {
        i++;
        out.writeln(
          '  $i. [$path:${l + 1}] ${lines[l].trim().replaceFirst('// ', '')}',
        );
      }
    }
  }
  if (codegenFailed) {
    i++;
    out.writeln(
      '  $i. A codegen step FAILED above — diagnose, fix, and re-run it '
      'before anything else.',
    );
  }
  final skillDir = File(Platform.script.toFilePath()).parent.path;
  if (translationFiles.isNotEmpty) {
    i++;
    out.writeln(
      '  $i. Translate: fill EVERY empty locale slot in '
      'specs/${n.f}.i18n.json (ONE Write covers all locales; each key '
      'carries its usage context), then apply with:\n'
      '       dart run $skillDir/apply_translations.dart '
      'specs/${n.f}.i18n.json\n'
      '     Never edit .arb files by hand — the apply script merges values '
      'and re-runs gen-l10n itself.',
    );
  }
  i++;
  out.writeln(
    '  $i. Wire the entry point on the default authenticated surface '
    '(lib/features/home/ui/pages/home_page.dart) — one Edit, no reading '
    'around; adapt this snippet to the neighboring children:\n'
    '       Semantics(\n'
    "         identifier: 'home-${n.fKebab}',\n"
    '         button: true,\n'
    '         child: /* house button/row widget — see REUSE INVENTORY */ (\n'
    '           onTap: () => context.pushNamed(AppRoutes.${n.fCamel}.name),\n'
    '         ),\n'
    '       ),',
  );
  for (final o in n.mutations) {
    i++;
    out.writeln(
      '  $i. Wire the "${o.name}" action in the UI (placement is your design '
      '— swipe, menu, or button; give it Semantics identifier '
      "'${n.fKebab}-${_snake(o.name).replaceAll('_', '-')}'):\n"
      '${o.confirm ? '       _confirm${o.pascal}(context, item.id)  '
          '// stamped helper: shows the confirm sheet, then runs the action' : '       context.read<${n.fPascal}Cubit>().${o.name}(item.id)'}',
    );
  }
  for (final task in _docTasks(n)) {
    i++;
    out.writeln('  $i. $task');
  }
  i++;
  out.writeln(
    '  $i. GATE — one command, fix any FAIL, re-run until PASS:\n'
    '       dart run $skillDir/verify_feature.dart',
  );

  out.write(_alreadyHandled(n));
  out.write(_projectFacts(n));

  out.writeln(
    '\nDo NOT restructure the stamped files — they are the project '
    'convention. Only the tasks above and genuinely feature-specific '
    'requirements need new code.',
  );

  final report = out.toString();
  final tasksPath = 'specs/${n.f}.tasks.md';
  File(tasksPath).parent.createSync(recursive: true);
  File(tasksPath).writeAsStringSync(report);
  stdout.writeln('\n$report');
  stdout.writeln('(This report is also saved at $tasksPath — re-read it from '
      'there instead of re-running or re-deriving anything above.)');
}

// ---------------------------------------------------------------------------
// project facts — mechanically extracted so the agent never greps for them
// ---------------------------------------------------------------------------

String _alreadyHandled(Names n) {
  final b = StringBuffer()
    ..writeln('\nREQUIREMENTS ALREADY SATISFIED BY THE STAMP — map prompt '
        'requirements to these bullets instead of grepping to verify:')
    ..writeln('  - Offline / connectivity: repositories return the wide seam '
        'Either<Failure, T> with mapBusiness pass-through, so transport '
        'failures render the app-wide offline copy via failure.getTitle('
        'context) in _ErrorContent. Proven by the stamped test "transport '
        'failures pass through unchanged (wide seam)".')
    ..writeln('  - Pull-to-refresh: RefreshIndicator wired to cubit.refresh() '
        'in ${n.f}_page.dart (deliberately unguarded — Rule 1 carve-out).')
    ..writeln('  - Loading / empty / error+retry states: the status switch in '
        '${n.f}_page.dart, incl. keep-list-visible-on-refresh.')
    ..writeln('  - Double-fire guard on load(), isClosed after every await, '
        'one-shot error field. Failures surface to the USER via the global '
        'AppBlocObserver SnackBar (addError → getTitle) — do NOT add a '
        'duplicate error surface unless the requirements explicitly demand '
        'inline display.');
  for (final o in n.mutations) {
    b.writeln('  - ${o.pascal}: cubit method ${o.name}(id) is stamped — '
        'in-flight guarded, reloads the list on success; on error its '
        'localized failure reaches the user via the global SnackBar '
        '(proven by 4 stamped tests). Only the UI trigger is yours'
        '${o.confirm ? ' — and the confirm sheet is already stamped as '
            '_confirm${o.pascal}()' : ''}.');
  }
  b
    ..writeln('  - Semantics identifiers on every stamped interactable '
        '(cards, retry buttons).')
    ..writeln('  - Signed-in only: new routes default to the authenticated '
        'class; no guard-list registration needed.');
  if (n.hasDetail) {
    b.writeln('  - Deep-linkable detail: /${n.fKebab}/:id route, cubit loads '
        'by id, retry re-loads.');
  }
  b.writeln('  - Localization: every user-facing string reads '
      'context.localization.<key>; keys exist in every locale (English '
      'defaults until you apply the i18n file).');
  return b.toString();
}

List<String> _docTasks(Names n) {
  if (!Directory('docs/business/features').existsSync()) return const [];
  final exemplar = Directory('docs/business/features')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.md'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final ex = exemplar.isEmpty ? '' : ' (mirror the structure of '
      '${exemplar.first.path})';
  return [
    'Per .claude/rules/documentation-requirements.md: write '
        'docs/business/features/${n.f}.md and docs/mobile/${n.f}/README.md'
        '$ex, and add nav entries / business-rule sections where the '
        'existing docs index features.',
  ];
}

String _projectFacts(Names n) {
  // Single source of truth: the project's own facts script (also served by
  // the /project-facts skill). Fall back to inline extraction without it.
  if (File('tools/print_project_facts.dart').existsSync()) {
    final r = Process.runSync('dart', ['tools/print_project_facts.dart']);
    if (r.exitCode == 0 && (r.stdout as String).trim().isNotEmpty) {
      return '\nPROJECT FACTS — extracted from this repo just now; use these '
          'directly, do NOT grep for them (same content as /project-facts):\n'
          '${r.stdout}';
    }
  }
  return '\nPROJECT FACTS: tools/print_project_facts.dart not found in this project — token roles and the reuse inventory must be discovered manually. (Install the facts script for zero-grep runs.)\n';
}



// ---------------------------------------------------------------------------
// spec parsing + validation
// ---------------------------------------------------------------------------

const _fieldTypes = {
  'String', 'String?', 'int', 'int?', 'double', 'double?', 'bool', 'bool?',
  'DateTime', 'DateTime?',
};

final _snakeRe = RegExp(r'^[a-z][a-z0-9_]*$');
final _camelRe = RegExp(r'^[a-z][a-zA-Z0-9]*$');
final _pascalRe = RegExp(r'^[A-Z][a-zA-Z0-9]*$');

class SpecField {
  SpecField({required this.name, required this.type, required this.column});
  final String name; // camelCase dart name
  final String type; // one of _fieldTypes
  final String column; // backend column

  bool get nullable => type.endsWith('?');
  String get baseType => nullable ? type.substring(0, type.length - 1) : type;
}

class SpecOperation {
  SpecOperation({
    required this.name,
    required this.kind,
    this.table,
    this.rpc,
    this.idParam,
    this.orderColumn,
    this.orderDesc = false,
    this.set = const {},
    this.confirm = false,
  });
  final String name; // camelCase method name
  final String kind; // list | single | delete | action
  final String? table; // table-based source
  final String? rpc; // rpc-based source (mutually exclusive with table)
  final String? idParam; // rpc id parameter name (single/delete/action)
  final String? orderColumn;
  final bool orderDesc;

  bool get isRpc => rpc != null;

  /// `action` only: fixed column assignments ("now" or a literal).
  final Map<String, Object?> set;

  /// delete/action: UI must ask for confirmation before invoking.
  final bool confirm;

  bool get isMutation => kind == 'delete' || kind == 'action';
  String get pascal => name[0].toUpperCase() + name.substring(1);
}

class SpecError {
  SpecError({required this.className, required this.code});
  final String className;
  final String code;
}

class Spec {
  Spec({
    required this.feature,
    required this.pages,
    required this.modelName,
    required this.fields,
    required this.operations,
    required this.errors,
  });

  final String feature;
  final List<String> pages;
  final String modelName;
  final List<SpecField> fields;
  final List<SpecOperation> operations;
  final List<SpecError> errors;

  static Spec? parse(Object? raw, List<String> errors) {
    if (raw is! Map<String, dynamic>) {
      errors.add('spec root must be a JSON object');
      return null;
    }
    const allowedTop = {
      'feature', 'pages', 'model', 'repository', 'operations', 'errors',
    };
    for (final k in raw.keys) {
      if (!allowedTop.contains(k)) {
        errors.add('unknown top-level key "$k" (allowed: $allowedTop)');
      }
    }

    final feature = raw['feature'];
    if (feature is! String || !_snakeRe.hasMatch(feature)) {
      errors.add('"feature" must be a snake_case string');
    }

    final pagesRaw = raw['pages'];
    var pages = const <String>[];
    if (pagesRaw is! List || pagesRaw.isEmpty) {
      errors.add('"pages" must be a non-empty array — v1 allows ["list"] or '
          '["list","detail"]');
    } else {
      pages = pagesRaw.map((e) => e.toString()).toList();
      if (pages.any((p) => p != 'list' && p != 'detail')) {
        errors.add('"pages" entries must be "list" or "detail"');
      }
      if (!pages.contains('list')) {
        errors.add('v1 requires a "list" page (detail-only is out of scope — '
            'use the normal pattern skills)');
      }
    }
    final hasDetail = pages.contains('detail');

    final repo = raw['repository'];
    if (repo != 'create') {
      errors.add('"repository" must be "create" — extending an existing '
          'repository is out of v1 scope (use the normal pattern skills)');
    }

    // model
    final model = raw['model'];
    var modelName = '';
    final fields = <SpecField>[];
    if (model is! Map<String, dynamic>) {
      errors.add('"model" must be an object with "name" and "fields"');
    } else {
      for (final k in model.keys) {
        if (k != 'name' && k != 'fields') {
          errors.add('unknown key "model.$k" (allowed: name, fields)');
        }
      }
      final mn = model['name'];
      if (mn is! String || !_snakeRe.hasMatch(mn)) {
        errors.add('"model.name" must be a snake_case string (singular)');
      } else {
        modelName = mn;
      }
      final fs = model['fields'];
      if (fs is! List || fs.isEmpty) {
        errors.add('"model.fields" must be a non-empty array');
      } else {
        final seen = <String>{};
        for (final (idx, f) in fs.indexed) {
          if (f is! Map<String, dynamic>) {
            errors.add('model.fields[$idx] must be an object');
            continue;
          }
          for (final k in f.keys) {
            if (k != 'name' && k != 'type' && k != 'column') {
              errors.add('unknown key model.fields[$idx].$k '
                  '(allowed: name, type, column)');
            }
          }
          final name = f['name'];
          final type = f['type'];
          if (name is! String || !_camelRe.hasMatch(name)) {
            errors.add('model.fields[$idx].name must be camelCase');
            continue;
          }
          if (!seen.add(name)) {
            errors.add('duplicate model field "$name"');
          }
          if (type is! String || !_fieldTypes.contains(type)) {
            errors.add('model.fields[$idx].type must be one of $_fieldTypes');
            continue;
          }
          final column = f['column'] ?? _snake(name);
          if (column is! String || !_snakeRe.hasMatch(column)) {
            errors.add('model.fields[$idx].column must be snake_case');
            continue;
          }
          fields.add(SpecField(name: name, type: type, column: column));
        }
        if (!fields.any((f) => f.name == 'id' && f.type == 'String')) {
          errors.add('model.fields must include an "id" field of type String '
              '(list tap + detail load key on it)');
        }
      }
    }

    // operations
    final opsRaw = raw['operations'];
    final ops = <SpecOperation>[];
    if (opsRaw is! List || opsRaw.isEmpty) {
      errors.add('"operations" must be a non-empty array');
    } else {
      for (final (idx, o) in opsRaw.indexed) {
        if (o is! Map<String, dynamic>) {
          errors.add('operations[$idx] must be an object');
          continue;
        }
        for (final k in o.keys) {
          if (!{'name', 'kind', 'source', 'confirm'}.contains(k)) {
            errors.add('unknown key operations[$idx].$k '
                '(allowed: name, kind, source, confirm)');
          }
        }
        final name = o['name'];
        final kind = o['kind'];
        final source = o['source'];
        if (name is! String || !_camelRe.hasMatch(name)) {
          errors.add('operations[$idx].name must be camelCase');
          continue;
        }
        if (!{'list', 'single', 'delete', 'action'}.contains(kind)) {
          errors.add('operations[$idx].kind must be "list", "single", '
              '"delete", or "action" — forms, RPC, and other mutation shapes '
              'are out of scope (use the normal pattern skills)');
          continue;
        }
        if (source is! Map<String, dynamic>) {
          errors.add('operations[$idx].source must be an object with "table" '
              '(+ "order" for list; "byId": true for single/delete/action; '
              '"set" for action)');
          continue;
        }
        for (final k in source.keys) {
          if (!{'table', 'order', 'byId', 'set', 'rpc', 'idParam'}
              .contains(k)) {
            errors.add('unknown key operations[$idx].source.$k '
                '(allowed: table, order, byId, set, rpc, idParam) — filters '
                'and extra RPC params are out of scope');
          }
        }
        final rpc = source['rpc'];
        final idParam = source['idParam'];
        if (rpc != null && source['table'] != null) {
          errors.add('operations[$idx].source: "table" and "rpc" are '
              'mutually exclusive — pick one');
          continue;
        }
        if (rpc != null) {
          if (rpc is! String || !_snakeRe.hasMatch(rpc)) {
            errors.add('operations[$idx].source.rpc must be a snake_case '
                'backend function name');
            continue;
          }
          if (source['order'] != null) {
            errors.add('operations[$idx]: "order" is table-only — an RPC '
                'defines its own ordering');
          }
          if (source['byId'] != null) {
            errors.add('operations[$idx]: "byId" is table-only — for RPC, '
                'use "idParam" instead');
          }
          if (kind == 'list') {
            if (idParam != null) {
              errors.add('operations[$idx]: "idParam" does not apply to a '
                  '"list" RPC (id-less call)');
            }
          } else if (idParam is! String || !_snakeRe.hasMatch(idParam)) {
            errors.add('operations[$idx]: RPC "$kind" requires "idParam" — '
                'the snake_case parameter that receives the row id (extra '
                'params are out of scope; use the pattern skills)');
          }
          if (kind == 'action' && source['set'] != null) {
            errors.add('operations[$idx]: "set" is table-only — an RPC '
                'encapsulates its own effect');
            continue;
          }
        } else if (idParam != null) {
          errors.add('operations[$idx]: "idParam" only applies with "rpc"');
        }
        if (o['confirm'] != null &&
            (o['confirm'] is! bool ||
                (kind != 'delete' && kind != 'action'))) {
          errors.add('operations[$idx].confirm must be a bool and only '
              'applies to delete/action operations');
        }
        final setRaw = source['set'];
        final setMap = <String, Object?>{};
        if (kind == 'action' && rpc == null) {
          if (setRaw is! Map<String, dynamic> || setRaw.isEmpty) {
            errors.add('operations[$idx]: kind "action" requires source.set '
                '— a non-empty map of column: value ("now" or a literal)');
            continue;
          }
          for (final e in setRaw.entries) {
            if (!_snakeRe.hasMatch(e.key)) {
              errors.add('operations[$idx].source.set: column "${e.key}" '
                  'must be snake_case');
            }
            if (e.value is! String && e.value is! num && e.value is! bool &&
                e.value != null) {
              errors.add('operations[$idx].source.set.${e.key}: value must '
                  'be "now", a literal string/number/bool, or null');
            }
            setMap[e.key] = e.value;
          }
        } else if (setRaw != null) {
          errors.add('operations[$idx]: "set" only applies to kind "action"');
        }
        if ((kind == 'delete' || kind == 'action') &&
            rpc == null &&
            source['byId'] != true) {
          errors.add('operations[$idx]: kind "$kind" requires "byId": true '
              '(other targeting is out of scope)');
        }
        final table = source['table'];
        if (rpc == null && (table is! String || !_snakeRe.hasMatch(table))) {
          errors.add('operations[$idx].source.table must be snake_case '
              '(or use "rpc")');
          continue;
        }
        String? orderColumn;
        var orderDesc = false;
        final order = source['order'];
        if (order != null) {
          if (kind != 'list') {
            errors.add('operations[$idx]: "order" only applies to kind "list"');
          } else if (order is! Map<String, dynamic> ||
              order['column'] is! String) {
            errors.add('operations[$idx].source.order must be '
                '{"column": <snake>, "desc": <bool>}');
          } else {
            orderColumn = order['column'] as String;
            orderDesc = order['desc'] == true;
            if (!_snakeRe.hasMatch(orderColumn)) {
              errors.add('operations[$idx].source.order.column must be '
                  'snake_case');
            }
          }
        }
        if (kind == 'single' && rpc == null && source['byId'] != true) {
          errors.add('operations[$idx]: kind "single" requires '
              '"byId": true (fetch-by-other-key is out of v1 scope)');
        }
        ops.add(SpecOperation(
          name: name,
          kind: kind as String,
          table: rpc == null ? table as String : null,
          rpc: rpc as String?,
          idParam: idParam as String?,
          orderColumn: orderColumn,
          orderDesc: orderDesc,
          set: setMap,
          confirm: o['confirm'] == true,
        ));
      }
      const reserved = {'load', 'refresh', 'close', 'emit', 'state', 'stream', 'isClosed', 'onChange', 'addError', 'onError'};
      final seenOps = <String>{};
      for (final o in ops) {
        if (reserved.contains(o.name)) {
          errors.add('operation name "${o.name}" collides with a stamped '
              'cubit member — pick another name');
        }
        if (!seenOps.add(o.name)) {
          errors.add('duplicate operation name "${o.name}"');
        }
      }
      final tables = ops.map((o) => o.table).whereType<String>().toSet();
      if (tables.length > 1) {
        errors.add('all table-based operations must target the SAME table '
            'in v1 (found: ${tables.join(', ')}) — multi-table features are '
            'out of scope');
      }
      final listOps = ops.where((o) => o.kind == 'list').length;
      final singleOps = ops.where((o) => o.kind == 'single').length;
      if (listOps != 1) {
        errors.add('exactly one operation of kind "list" is required '
            '(found $listOps)');
      }
      if (hasDetail && singleOps != 1) {
        errors.add('a "detail" page requires exactly one operation of kind '
            '"single" (found $singleOps)');
      }
      if (!hasDetail && singleOps > 0) {
        errors.add('a "single" operation requires a "detail" page');
      }
      if (ops.any((o) => o.isMutation) && listOps == 0) {
        errors.add('mutations require a "list" operation (the cubit reloads '
            'the list after a successful mutation)');
      }
    }

    // errors
    final errsRaw = raw['errors'] ?? const [];
    final specErrors = <SpecError>[];
    if (errsRaw is! List) {
      errors.add('"errors" must be an array (may be empty)');
    } else {
      for (final (idx, e) in errsRaw.indexed) {
        if (e is! Map<String, dynamic>) {
          errors.add('errors[$idx] must be an object');
          continue;
        }
        for (final k in e.keys) {
          if (k != 'class' && k != 'code') {
            errors.add('unknown key errors[$idx].$k (allowed: class, code)');
          }
        }
        final cls = e['class'];
        final code = e['code'];
        if (cls is! String ||
            !_pascalRe.hasMatch(cls) ||
            !cls.endsWith('Failure')) {
          errors.add('errors[$idx].class must be PascalCase ending in '
              '"Failure"');
          continue;
        }
        if (code is! String || !_snakeRe.hasMatch(code)) {
          errors.add('errors[$idx].code must be snake_case');
          continue;
        }
        specErrors.add(SpecError(className: cls, code: code));
      }
    }

    final mutFailures =
        ops.where((o) => o.isMutation).map((o) => '${o.pascal}Failure').toSet();
    final seenErrors = {if (feature is String) '${Names._pascal(feature)}LoadFailure'};
    for (final e in specErrors) {
      if (!seenErrors.add(e.className)) {
        errors.add('errors[].class "${e.className}" is already declared');
      }
      if (mutFailures.contains(e.className)) {
        errors.add('errors[].class "${e.className}" collides with the '
            'generated failure for the same-named mutation');
      }
    }

    if (errors.isNotEmpty) return null;
    return Spec(
      feature: feature as String,
      pages: pages,
      modelName: modelName,
      fields: fields,
      operations: ops,
      errors: specErrors,
    );
  }
}

String _snake(String camel) => camel
    .replaceAllMapped(RegExp('([A-Z])'), (m) => '_${m.group(1)!.toLowerCase()}');

// ---------------------------------------------------------------------------
// derived names + sample values
// ---------------------------------------------------------------------------

class Names {
  Names({required this.spec, required this.package});

  final Spec spec;
  final String package;

  String get f => spec.feature;
  String get m => spec.modelName;
  String get fPascal => _pascal(f);
  String get fCamel => _camelOf(fPascal);
  String get fKebab => f.replaceAll('_', '-');
  String get mPascal => _pascal(m);
  String get mCamel => _camelOf(mPascal);
  bool get hasDetail => spec.pages.contains('detail');

  SpecOperation get listOp => spec.operations.firstWhere((o) => o.kind == 'list');
  SpecOperation? get singleOp =>
      spec.operations.where((o) => o.kind == 'single').firstOrNull;
  List<SpecOperation> get mutations =>
      spec.operations.where((o) => o.isMutation).toList();

  String mutationFailureClass(SpecOperation o) => '${o.pascal}Failure';
  String mutationArbKey(SpecOperation o) => '${fCamel}Error${o.pascal}';
  String mutationWords(SpecOperation o) => o.name
      .replaceAllMapped(RegExp('(?<=[a-z])(?=[A-Z])'), (_) => ' ')
      .toLowerCase();

  /// Dart literal for an `action` assignment value ("now" => UTC timestamp).
  String setValueLiteral(Object? v) {
    if (v == 'now') return 'DateTime.now().toUtc().toIso8601String()';
    if (v is String) {
      final escaped = v
          .replaceAllMapped(RegExp(r"[\\$']"), (m) => '\\${m[0]}')
          .replaceAll('\n', r'\n')
          .replaceAll('\r', r'\r');
      return "'$escaped'";
    }
    return '$v';
  }

  /// Field rendered in the stamped list tile / detail headline.
  SpecField get displayField =>
      spec.fields.where((x) => x.baseType == 'String' && x.name != 'id').firstOrNull ??
      spec.fields.firstWhere((x) => x.name == 'id');

  String get idColumn => spec.fields.firstWhere((x) => x.name == 'id').column;

  /// ARB key for an extra error class: strip feature prefix + Failure suffix.
  String errorArbKey(SpecError e) {
    var core = e.className;
    if (core.startsWith(fPascal)) core = core.substring(fPascal.length);
    if (core.startsWith(mPascal)) core = core.substring(mPascal.length);
    if (core.endsWith('Failure')) {
      core = core.substring(0, core.length - 'Failure'.length);
    }
    if (core.isEmpty) core = 'Error';
    return '${fCamel}Error$core';
  }

  /// Dart literal sample value for a field (i = 1-based sample index).
  /// Sample 2 exercises the "absent" variants: null for nullable fields,
  /// false for bools — so previews show both states out of the box.
  String? sample(SpecField x, int i) {
    if (x.nullable && i.isEven) return null;
    final v = switch (x.baseType) {
      'String' => x.name == 'id' ? "'$i'" : "'Sample ${x.name} $i'",
      'int' => '$i',
      'double' => '$i.0',
      'bool' => i.isEven ? 'false' : 'true',
      'DateTime' => 'DateTime.utc(2026, 1, $i)',
      _ => "''",
    };
    return v;
  }

  String sampleCtor(int i) {
    final args = spec.fields
        .map((x) => (x, sample(x, i)))
        .where((e) => e.$2 != null)
        .map((e) => '${e.$1.name}: ${e.$2}')
        .join(', ');
    return '$mPascal' 'Response($args)';
  }

  bool get samplesConst =>
      !spec.fields.any((x) => x.baseType == 'DateTime');

  /// Whether sample row [i] can be const on its own (no DateTime rendered).
  bool sampleRowConst(int i) => !spec.fields
      .any((x) => (sample(x, i) ?? '').contains('DateTime'));

  static String _pascal(String s) =>
      s.split('_').map((w) => w[0].toUpperCase() + w.substring(1)).join();
  static String _camelOf(String p) => p[0].toLowerCase() + p.substring(1);
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

// ---------------------------------------------------------------------------
// templates
// ---------------------------------------------------------------------------

String failureT(Names n) {
  final extra = StringBuffer();
  for (final o in n.mutations) {
    extra.write('''

/// ${o.pascal} failed for a non-transport reason.
class ${n.mutationFailureClass(o)} extends ${n.fPascal}Failure {
  const ${n.mutationFailureClass(o)}({super.code = '${_snake(o.name)}_failed'});

  @override
  String getTitle(BuildContext context) =>
      context.localization.${n.mutationArbKey(o)};
}
''');
  }
  for (final e in n.spec.errors) {
    extra.write('''

/// ${e.className} — backend/business case `${e.code}`.
class ${e.className} extends ${n.fPascal}Failure {
  const ${e.className}({super.code = '${e.code}'});

  @override
  String getTitle(BuildContext context) =>
      context.localization.${n.errorArbKey(e)};
}
''');
  }
  return '''
import 'package:${n.package}/core/localization/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:simple_network_handler/simple_network_handler_supabase.dart';

/// Base class for ${n.f} failures.
///
/// Transport failures (offline/timeout) are NEVER re-mapped into these —
/// repositories pass them through unchanged (wide seam), so connectivity
/// renders the one app-wide message.
abstract class ${n.fPascal}Failure extends Failure {
  const ${n.fPascal}Failure({this.code = '${n.f}_error'});

  /// Diagnostic code — for logs/observability, never user copy.
  final String code;

  @override
  String getTitle(BuildContext context) =>
      context.localization.${n.fCamel}ErrorGeneric;

  /// Localized or empty — never the raw [code].
  @override
  String getSubtitle(BuildContext context) => '';
}

/// Loading ${n.f} failed for a non-transport reason.
class ${n.fPascal}LoadFailure extends ${n.fPascal}Failure {
  const ${n.fPascal}LoadFailure({super.code = 'load_failed'});

  @override
  String getTitle(BuildContext context) =>
      context.localization.${n.fCamel}ErrorLoadFailed;
}
$extra''';
}

String modelT(Names n) {
  final fields = StringBuffer();
  final ordered = [
    ...n.spec.fields.where((x) => !x.nullable),
    ...n.spec.fields.where((x) => x.nullable),
  ];
  for (final x in ordered) {
    final jsonKey = x.column == x.name
        ? ''
        : "    @JsonKey(name: '${x.column}')\n";
    fields.write('''
    /// Backend column `${x.column}`.
$jsonKey    ${x.nullable ? '' : 'required '}${x.type} ${x.name},

''');
  }
  return '''
import 'package:freezed_annotation/freezed_annotation.dart';

part '../../../../../core/generated/features/${n.f}/logic/models/responses/${n.m}_response.freezed.dart';
part '../../../../../core/generated/features/${n.f}/logic/models/responses/${n.m}_response.g.dart';

/// One ${n.m} row as returned by the backend (fields from the feature spec).
@freezed
abstract class ${n.mPascal}Response with _\$${n.mPascal}Response {
  const factory ${n.mPascal}Response({
${fields.toString().trimRight()}
  }) = _${n.mPascal}Response;

  factory ${n.mPascal}Response.fromJson(Map<String, dynamic> json) =>
      _\$${n.mPascal}ResponseFromJson(json);
}
''';
}

String repositoryT(Names n) {
  final single = n.singleOp;
  final mut = StringBuffer();
  for (final o in n.mutations) {
    mut.write('''

  /// ${o.pascal} — by id.${o.confirm ? ' UI confirms before calling.' : ''}
  Future<Either<Failure, void>> ${o.name}(String id);
''');
  }
  return '''
import 'package:${n.package}/features/${n.f}/logic/models/responses/${n.m}_response.dart';
import 'package:simple_network_handler/simple_network_handler_supabase.dart';

/// Data operations for the ${n.f} feature.
///
/// Every method returns the WIDE seam `Either<Failure, T>` — never
/// `Either<${n.fPascal}Failure, T>` — so transport failures pass through
/// unchanged and render the app-wide connection message.
abstract class ${n.fPascal}Repository {
  /// Loads all ${n.f}.
  Future<Either<Failure, List<${n.mPascal}Response>>> ${n.listOp.name}();
${single == null ? '' : '''

  /// Loads a single ${n.m} by [id].
  Future<Either<Failure, ${n.mPascal}Response>> ${single.name}(String id);
'''}$mut}
''';
}

String repositoryImplT(Names n) {
  final listOp = n.listOp;
  final single = n.singleOp;
  final order = listOp.orderColumn == null
      ? ''
      : "\n          .order('${listOp.orderColumn}', ascending: ${!listOp.orderDesc})";
  final tableOps = n.spec.operations.where((o) => !o.isRpc).toList();
  final tableConst = tableOps.isEmpty
      ? ''
      : "\n  static const _table = '${tableOps.first.table}';\n";
  final listCall = listOp.isRpc
      ? "_client.rpc('${listOp.rpc}')"
      : '_client\n          .from(_table)\n          .select()$order';
  final singleCall = single == null
      ? ''
      : single.isRpc
          ? "_client.rpc('${single.rpc}', params: {'${single.idParam}': id})"
          : "_client.from(_table).select().eq('${n.idColumn}', id).single()";
  return '''
import 'package:${n.package}/features/${n.f}/logic/failures/${n.f}_failure.dart';
import 'package:${n.package}/features/${n.f}/logic/models/responses/${n.m}_response.dart';
import 'package:${n.package}/features/${n.f}/logic/repositories/${n.f}_repository.dart';
import 'package:injectable/injectable.dart';
import 'package:simple_network_handler/simple_network_handler_supabase.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// Supabase implementation of [${n.fPascal}Repository].
@LazySingleton(as: ${n.fPascal}Repository)
class ${n.fPascal}RepositoryImpl implements ${n.fPascal}Repository {
  ${n.fPascal}RepositoryImpl(this._client);

  final supabase.SupabaseClient _client;
$tableConst
  @override
  Future<Either<Failure, List<${n.mPascal}Response>>> ${listOp.name}() async {
    final result = await SupabaseNetworkHandler.safeCall<List<dynamic>>(
      () => $listCall,
    );

    // mapBusiness: transport failures pass through unchanged (app-wide
    // offline copy); anything else collapses to the feature fallback.
    return result.mapBusiness(
      const ${n.fPascal}LoadFailure(),
      (data) {
        // Parse inside the fold guarded by try/catch: a malformed row must
        // become a Left, not an uncaught TypeError that strands the UI on
        // loading.
        try {
          final items = data
              .map((json) =>
                  ${n.mPascal}Response.fromJson(json as Map<String, dynamic>))
              .toList();
          return Right(items);
        } catch (_) {
          return const Left(${n.fPascal}LoadFailure());
        }
      },
    );
  }
${single == null ? '' : '''

  @override
  Future<Either<Failure, ${n.mPascal}Response>> ${single.name}(String id) async {
    final result = await SupabaseNetworkHandler.safeCall<Map<String, dynamic>>(
      () => $singleCall,
    );

    return result.mapBusiness(
      const ${n.fPascal}LoadFailure(),
      (data) {
        try {
          return Right(${n.mPascal}Response.fromJson(data));
        } catch (_) {
          return const Left(${n.fPascal}LoadFailure());
        }
      },
    );
  }
'''}${n.mutations.map((o) {
    final call = o.isRpc
        ? "_client.rpc('${o.rpc}', params: {'${o.idParam}': id})"
        : o.kind == 'delete'
            ? "_client.from(_table).delete().eq('${n.idColumn}', id)"
            : "_client.from(_table).update({${o.set.entries.map((e) => "'${e.key}': ${n.setValueLiteral(e.value)}").join(', ')}}).eq('${n.idColumn}', id)";
    return '''

  @override
  Future<Either<Failure, void>> ${o.name}(String id) async {
    final result = await SupabaseNetworkHandler.safeCall<void>(
      () => $call,
    );

    return result.mapBusiness(
      const ${n.mutationFailureClass(o)}(),
      (_) => const Right(null),
    );
  }
''';
  }).join()}}
''';
}

String listStateT(Names n) => '''
import 'package:${n.package}/core/utils/bloc_status.dart';
import 'package:${n.package}/features/${n.f}/logic/models/responses/${n.m}_response.dart';
import 'package:equatable/equatable.dart';
import 'package:simple_network_handler/simple_network_handler_supabase.dart';

/// State for [${n.fPascal}Cubit] — shared [BlocStatus], manual `copyWith`.
class ${n.fPascal}State extends Equatable {
  const ${n.fPascal}State({
    this.status = BlocStatus.initial,
    this.items = const [],
    this.error,
  });

  final BlocStatus status;

  /// Loaded ${n.f}.
  final List<${n.mPascal}Response> items;

  /// One-shot failure — rendered via `error!.getTitle(context)` at build time.
  final Failure? error;

  // Add feature-specific state fields here only if the requirements need
  // them (persistent fields use `?? this.field` in copyWith).

  /// [error] is ONE-SHOT: assigned directly, so any `copyWith` that does not
  /// pass it clears it. Persistent fields use `?? this.field`.
  ${n.fPascal}State copyWith({
    BlocStatus? status,
    List<${n.mPascal}Response>? items,
    Failure? error,
  }) {
    return ${n.fPascal}State(
      status: status ?? this.status,
      items: items ?? this.items,
      error: error,
    );
  }

  @override
  List<Object?> get props => [status, items, error];
}
''';

String listCubitT(Names n) => '''
import 'package:${n.package}/core/utils/bloc_status.dart';
import 'package:${n.package}/features/${n.f}/logic/cubit/${n.f}_state.dart';
import 'package:${n.package}/features/${n.f}/logic/repositories/${n.f}_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

/// Cubit for the ${n.f} list page.
@injectable
class ${n.fPascal}Cubit extends Cubit<${n.fPascal}State> {
  ${n.fPascal}Cubit(this._repository) : super(const ${n.fPascal}State());

  final ${n.fPascal}Repository _repository;
${n.mutations.map((o) => '  bool _${o.name}InFlight = false;\n').join()}
  /// Initial load — guarded against double-fire.
  Future<void> load() async {
    if (state.status == BlocStatus.loading) return;
    await _fetch();
  }

  /// Pull-to-refresh — deliberately unguarded: restarting a slow load is
  /// legitimate here (cubit-creation Rule 1 carve-out).
  Future<void> refresh() => _fetch();

  Future<void> _fetch() async {
    emit(state.copyWith(status: BlocStatus.loading));

    final result = await _repository.${n.listOp.name}();
    if (isClosed) return;

    result.fold(
      (failure) {
        emit(state.copyWith(status: BlocStatus.failure, error: failure));
        addError(failure, StackTrace.current);
      },
      (items) =>
          emit(state.copyWith(status: BlocStatus.success, items: items)),
    );
  }
${n.mutations.map((o) => '''

  /// ${o.pascal} — guarded against double-fire; reloads the list on success.
  Future<void> ${o.name}(String id) async {
    if (_${o.name}InFlight) return;
    _${o.name}InFlight = true;
    try {
      final result = await _repository.${o.name}(id);
      if (isClosed) return;

      final failure = result.fold((f) => f, (_) => null);
      if (failure != null) {
        emit(state.copyWith(status: BlocStatus.failure, error: failure));
        addError(failure, StackTrace.current);
        return;
      }
      await _fetch();
    } finally {
      _${o.name}InFlight = false;
    }
  }''').join()}

  // Add feature-specific operations here only if the requirements ask for
  // them (guard user actions, `if (isClosed) return;` after every await).
}
''';

String detailStateT(Names n) => '''
import 'package:${n.package}/core/utils/bloc_status.dart';
import 'package:${n.package}/features/${n.f}/logic/models/responses/${n.m}_response.dart';
import 'package:equatable/equatable.dart';
import 'package:simple_network_handler/simple_network_handler_supabase.dart';

/// State for [${n.mPascal}DetailCubit].
class ${n.mPascal}DetailState extends Equatable {
  const ${n.mPascal}DetailState({
    this.status = BlocStatus.initial,
    this.item,
    this.error,
  });

  final BlocStatus status;

  /// The loaded ${n.m}, null until [BlocStatus.success].
  final ${n.mPascal}Response? item;

  /// One-shot failure — rendered via `error!.getTitle(context)` at build time.
  final Failure? error;

  /// [error] is ONE-SHOT: assigned directly, so any `copyWith` that does not
  /// pass it clears it. Persistent fields use `?? this.field`.
  ${n.mPascal}DetailState copyWith({
    BlocStatus? status,
    ${n.mPascal}Response? item,
    Failure? error,
  }) {
    return ${n.mPascal}DetailState(
      status: status ?? this.status,
      item: item ?? this.item,
      error: error,
    );
  }

  @override
  List<Object?> get props => [status, item, error];
}
''';

String detailCubitT(Names n) => '''
import 'package:${n.package}/core/utils/bloc_status.dart';
import 'package:${n.package}/features/${n.f}/logic/cubit/${n.m}_detail_state.dart';
import 'package:${n.package}/features/${n.f}/logic/repositories/${n.f}_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

/// Cubit for the ${n.m} detail page.
@injectable
class ${n.mPascal}DetailCubit extends Cubit<${n.mPascal}DetailState> {
  ${n.mPascal}DetailCubit(this._repository)
      : super(const ${n.mPascal}DetailState());

  final ${n.fPascal}Repository _repository;

  /// Loads the ${n.m} with [id] — guarded against double-fire.
  Future<void> load(String id) async {
    if (state.status == BlocStatus.loading) return;

    emit(state.copyWith(status: BlocStatus.loading));

    final result = await _repository.${n.singleOp!.name}(id);
    if (isClosed) return;

    result.fold(
      (failure) {
        emit(state.copyWith(status: BlocStatus.failure, error: failure));
        addError(failure, StackTrace.current);
      },
      (item) => emit(state.copyWith(status: BlocStatus.success, item: item)),
    );
  }
}
''';

String listPageT(Names n) {
  final detail = n.hasDetail;
  final confirmOps = n.mutations.where((o) => o.confirm).toList();
  // Widget-tier imports, alphabetically sorted so directives_ordering holds
  // whichever subset stamps.
  final widgetNames = <String>[
    'empty_state',
    'error_state',
    'top_bar',
    if (confirmOps.isNotEmpty) ...['bottom_sheet_modal', 'ghost_button', 'primary_button'],
  ]..sort();
  final widgetImports = widgetNames
      .map((w) => "import 'package:${n.package}/core/widgets/$w.dart';\n")
      .join();
  final confirmHelpers = confirmOps.map((o) => '''

/// Confirm-then-${o.name}: shows the house confirm sheet; runs on confirm.
/// Call this from your UI trigger — never call cubit.${o.name} directly.
Future<void> _confirm${o.pascal}(BuildContext context, String id) async {
  final l = context.localization;
  final cubit = context.read<${n.fPascal}Cubit>();
  final confirmed = await BottomSheetModal.show<bool>(
    context: context,
    icon: ${o.kind == 'delete' ? 'Icons.delete_outline_rounded' : 'Icons.check_circle_outline_rounded'},
    title: l.${n.fCamel}${o.pascal}ConfirmTitle,
    body: l.${n.fCamel}${o.pascal}ConfirmBody,
    isDismissible: true,
    actions: [
      PrimaryButton(
        semanticsIdentifier: '${n.fKebab}-${_snake(o.name).replaceAll('_', '-')}-confirm',
        label: l.${n.fCamel}${o.pascal}ConfirmAction,
        onPressed: () => Navigator.pop(context, true),
      ),
      GhostButton(
        semanticsIdentifier: '${n.fKebab}-${_snake(o.name).replaceAll('_', '-')}-cancel',
        label: l.${n.fCamel}ConfirmCancel,
        onPressed: () => Navigator.pop(context, false),
      ),
    ],
  );
  if (confirmed == true) {
    await cubit.${o.name}(id);
  }
}''').join();
  final display = n.displayField;
  final displayExpr = display.nullable
      ? 'item.${display.name} ?? item.id'
      : 'item.${display.name}';
  return '''
import 'package:${n.package}/core/injection/injection.dart';
import 'package:${n.package}/core/localization/localization_extension.dart';
${detail ? "import 'package:${n.package}/core/router/routes.dart';\n" : ''}import 'package:${n.package}/core/theme/theme.dart';
import 'package:${n.package}/core/utils/bloc_status.dart';
${widgetImports}import 'package:${n.package}/features/${n.f}/logic/cubit/${n.f}_cubit.dart';
import 'package:${n.package}/features/${n.f}/logic/cubit/${n.f}_state.dart';
import 'package:${n.package}/features/${n.f}/logic/models/responses/${n.m}_response.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
${detail ? "import 'package:go_router/go_router.dart';\n" : ''}import 'package:simple_network_handler/simple_network_handler_supabase.dart';

/// ${n.fPascal} list page — outer widget provides the cubit, inner view
/// consumes it.
class ${n.fPascal}Page extends StatelessWidget {
  const ${n.fPascal}Page({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<${n.fPascal}Cubit>()..load(),
      child: const _${n.fPascal}View(),
    );
  }
}

class _${n.fPascal}View extends StatelessWidget {
  const _${n.fPascal}View();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: TopBar(title: context.localization.${n.fCamel}Title),
      body: const SafeArea(child: _${n.fPascal}Body()),
    );
  }
}

class _${n.fPascal}Body extends StatelessWidget {
  const _${n.fPascal}Body();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<${n.fPascal}Cubit, ${n.fPascal}State>(
      buildWhen: (prev, curr) =>
          prev.status != curr.status ||
          prev.items != curr.items ||
          prev.error != curr.error,
      builder: (context, state) {
        return switch (state.status) {
          // First load: spinner. Later loads keep the list visible — the
          // `when state.items.isEmpty` guard distinguishes the two.
          BlocStatus.initial ||
          BlocStatus.loading when state.items.isEmpty =>
            Center(
              child: CircularProgressIndicator(color: context.colors.primary),
            ),
          BlocStatus.failure when state.items.isEmpty => _ErrorContent(
              failure: state.error,
              onRetry: () => context.read<${n.fPascal}Cubit>().refresh(),
            ),
          _ => _${n.fPascal}List(
              items: state.items,
              onRefresh: () async =>
                  context.read<${n.fPascal}Cubit>().refresh(),
            ),
        };
      },
    );
  }
}

class _${n.fPascal}List extends StatelessWidget {
  const _${n.fPascal}List({required this.items, required this.onRefresh});

  final List<${n.mPascal}Response> items;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return RefreshIndicator(
        color: context.colors.primary,
        onRefresh: onRefresh,
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.2),
            EmptyState(title: context.localization.${n.fCamel}Empty),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: context.colors.primary,
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(
          context.spacing.pagePadding,
          0,
          context.spacing.pagePadding,
          context.spacing.gapCozy,
        ),
        itemCount: items.length,
        separatorBuilder: (_, _) => Container(
          height: context.spacing.hairline,
          color: context.colors.divider,
        ),
        itemBuilder: (context, index) {
          final item = items[index];
          return Semantics(
            identifier: '${n.fKebab}-card-\$index',
            button: true,
            child: InkWell(
${detail ? '''              onTap: () => context.pushNamed(
                AppRoutes.${n.mCamel}Detail.name,
                pathParameters: {'id': item.id},
              ),
''' : '''              // TODO(ai): wire the tap action the requirements ask for.
              onTap: () {},
'''}              child: Padding(
                padding: EdgeInsets.symmetric(
                  vertical: context.spacing.gapNormal,
                ),
                // TODO(ai): design the real list tile for a ${n.m} (which
                // fields, layout) per the requirements — tokens only, no
                // literals.
                child: Text($displayExpr, style: context.styles.titleMedium),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ErrorContent extends StatelessWidget {
  const _ErrorContent({required this.failure, required this.onRetry});

  final Failure? failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    // The Failure carries its own localized copy (incl. the app-wide
    // offline message for transport failures).
    return ErrorState(
      message: failure?.getTitle(context) ??
          context.localization.${n.fCamel}ErrorLoadFailed,
      retrySemanticsIdentifier: '${n.fKebab}-retry',
      onRetry: onRetry,
    );
  }
}$confirmHelpers
''';
}

String detailPageT(Names n) {
  final display = n.displayField;
  final displayExpr = display.nullable
      ? 'item.${display.name} ?? item.id'
      : 'item.${display.name}';
  return '''
import 'package:${n.package}/core/injection/injection.dart';
import 'package:${n.package}/core/localization/localization_extension.dart';
import 'package:${n.package}/core/theme/theme.dart';
import 'package:${n.package}/core/utils/bloc_status.dart';
import 'package:${n.package}/core/widgets/error_state.dart';
import 'package:${n.package}/core/widgets/top_bar.dart';
import 'package:${n.package}/features/${n.f}/logic/cubit/${n.m}_detail_cubit.dart';
import 'package:${n.package}/features/${n.f}/logic/cubit/${n.m}_detail_state.dart';
import 'package:${n.package}/features/${n.f}/logic/models/responses/${n.m}_response.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:simple_network_handler/simple_network_handler_supabase.dart';

/// Detail page for a single ${n.m}, loaded by [id] (deep-linkable).
class ${n.mPascal}DetailPage extends StatelessWidget {
  const ${n.mPascal}DetailPage({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<${n.mPascal}DetailCubit>()..load(id),
      child: _${n.mPascal}DetailView(id: id),
    );
  }
}

class _${n.mPascal}DetailView extends StatelessWidget {
  const _${n.mPascal}DetailView({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: TopBar(title: context.localization.${n.fCamel}DetailTitle),
      body: SafeArea(
        child: BlocBuilder<${n.mPascal}DetailCubit, ${n.mPascal}DetailState>(
          builder: (context, state) {
            final item = state.item;
            return switch (state.status) {
              BlocStatus.initial || BlocStatus.loading => Center(
                  child: CircularProgressIndicator(
                    color: context.colors.primary,
                  ),
                ),
              BlocStatus.failure => _ErrorContent(
                  failure: state.error,
                  onRetry: () =>
                      context.read<${n.mPascal}DetailCubit>().load(id),
                ),
              BlocStatus.success when item != null =>
                _${n.mPascal}Content(item: item),
              _ => const SizedBox.shrink(),
            };
          },
        ),
      ),
    );
  }
}

class _${n.mPascal}Content extends StatelessWidget {
  const _${n.mPascal}Content({required this.item});

  final ${n.mPascal}Response item;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(context.spacing.pagePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // TODO(ai): design the real detail layout for a ${n.m} (which
          // fields, sections) per the requirements — tokens only, no
          // literals.
          Text($displayExpr, style: context.styles.titleLarge),
        ],
      ),
    );
  }
}

class _ErrorContent extends StatelessWidget {
  const _ErrorContent({required this.failure, required this.onRetry});

  final Failure? failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ErrorState(
      message: failure?.getTitle(context) ??
          context.localization.${n.fCamel}ErrorLoadFailed,
      retrySemanticsIdentifier: '${n.fKebab}-detail-retry',
      onRetry: onRetry,
    );
  }
}
''';
}

String useCaseT(Names n) {
  final kw = n.samplesConst ? 'const ' : 'final ';
  return '''
import 'package:${n.package}/core/utils/bloc_status.dart';
import 'package:${n.package}/features/${n.f}/logic/cubit/${n.f}_cubit.dart';
import 'package:${n.package}/features/${n.f}/logic/cubit/${n.f}_state.dart';
import 'package:${n.package}/features/${n.f}/logic/failures/${n.f}_failure.dart';
import 'package:${n.package}/features/${n.f}/logic/models/responses/${n.m}_response.dart';
import 'package:${n.package}/features/${n.f}/ui/pages/${n.f}_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

// The page reads its cubit via `getIt` in `BlocProvider.create`, so the fake
// is (re-)registered INTO GetIt — a `.value` above the page would be ignored.

class _Fake${n.fPascal}Cubit extends Cubit<${n.fPascal}State>
    implements ${n.fPascal}Cubit {
  _Fake${n.fPascal}Cubit(super.state);

  @override
  Future<void> load() async {}

  @override
  Future<void> refresh() async {}
${n.mutations.map((o) => '''

  @override
  Future<void> ${o.name}(String id) async {}''').join()}
}

void _ensureFake(${n.fPascal}State state) {
  final getIt = GetIt.instance;
  if (getIt.isRegistered<${n.fPascal}Cubit>()) {
    getIt.unregister<${n.fPascal}Cubit>();
  }
  getIt.registerFactory<${n.fPascal}Cubit>(() => _Fake${n.fPascal}Cubit(state));
}

// Sample data generated from the feature spec — extend if the model grows.
$kw _sampleItems = [
  ${n.samplesConst || !n.sampleRowConst(1) ? '' : 'const '}${n.sampleCtor(1)},
  ${n.samplesConst || !n.sampleRowConst(2) ? '' : 'const '}${n.sampleCtor(2)},
];

@widgetbook.UseCase(name: 'loaded', type: ${n.fPascal}Page)
Widget ${n.fCamel}PageLoadedUseCase(BuildContext context) {
  _ensureFake(
    ${n.samplesConst ? 'const ' : ''}${n.fPascal}State(status: BlocStatus.success, items: _sampleItems),
  );
  return const ${n.fPascal}Page();
}

@widgetbook.UseCase(name: 'empty', type: ${n.fPascal}Page)
Widget ${n.fCamel}PageEmptyUseCase(BuildContext context) {
  _ensureFake(const ${n.fPascal}State(status: BlocStatus.success));
  return const ${n.fPascal}Page();
}

@widgetbook.UseCase(name: 'loading', type: ${n.fPascal}Page)
Widget ${n.fCamel}PageLoadingUseCase(BuildContext context) {
  _ensureFake(const ${n.fPascal}State(status: BlocStatus.loading));
  return const ${n.fPascal}Page();
}

@widgetbook.UseCase(name: 'error', type: ${n.fPascal}Page)
Widget ${n.fCamel}PageErrorUseCase(BuildContext context) {
  _ensureFake(
    const ${n.fPascal}State(
      status: BlocStatus.failure,
      error: ${n.fPascal}LoadFailure(),
    ),
  );
  return const ${n.fPascal}Page();
}
''';
}

String detailUseCaseT(Names n) {
  final kw = n.samplesConst ? 'const ' : 'final ';
  return '''
import 'package:${n.package}/core/utils/bloc_status.dart';
import 'package:${n.package}/features/${n.f}/logic/cubit/${n.m}_detail_cubit.dart';
import 'package:${n.package}/features/${n.f}/logic/cubit/${n.m}_detail_state.dart';
import 'package:${n.package}/features/${n.f}/logic/failures/${n.f}_failure.dart';
import 'package:${n.package}/features/${n.f}/logic/models/responses/${n.m}_response.dart';
import 'package:${n.package}/features/${n.f}/ui/pages/${n.m}_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

// The page reads its cubit via `getIt` in `BlocProvider.create`, so the fake
// is (re-)registered INTO GetIt — a `.value` above the page would be ignored.

class _Fake${n.mPascal}DetailCubit extends Cubit<${n.mPascal}DetailState>
    implements ${n.mPascal}DetailCubit {
  _Fake${n.mPascal}DetailCubit(super.state);

  @override
  Future<void> load(String id) async {}
}

void _ensureFake(${n.mPascal}DetailState state) {
  final getIt = GetIt.instance;
  if (getIt.isRegistered<${n.mPascal}DetailCubit>()) {
    getIt.unregister<${n.mPascal}DetailCubit>();
  }
  getIt.registerFactory<${n.mPascal}DetailCubit>(
      () => _Fake${n.mPascal}DetailCubit(state));
}

// Sample generated from the feature spec — extend if the model grows.
$kw _sampleItem = ${n.sampleCtor(1)};

@widgetbook.UseCase(name: 'loaded', type: ${n.mPascal}DetailPage)
Widget ${n.mCamel}DetailPageLoadedUseCase(BuildContext context) {
  _ensureFake(
    ${n.samplesConst ? 'const ' : ''}${n.mPascal}DetailState(status: BlocStatus.success, item: _sampleItem),
  );
  return const ${n.mPascal}DetailPage(id: '1');
}

@widgetbook.UseCase(name: 'loading', type: ${n.mPascal}DetailPage)
Widget ${n.mCamel}DetailPageLoadingUseCase(BuildContext context) {
  _ensureFake(const ${n.mPascal}DetailState(status: BlocStatus.loading));
  return const ${n.mPascal}DetailPage(id: '1');
}

@widgetbook.UseCase(name: 'error', type: ${n.mPascal}DetailPage)
Widget ${n.mCamel}DetailPageErrorUseCase(BuildContext context) {
  _ensureFake(
    const ${n.mPascal}DetailState(
      status: BlocStatus.failure,
      error: ${n.fPascal}LoadFailure(),
    ),
  );
  return const ${n.mPascal}DetailPage(id: '1');
}
''';
}

String listCubitTestT(Names n) {
  final kw = n.samplesConst ? 'const ' : 'final ';
  final c = n.samplesConst ? 'const ' : '';
  final ec = n.samplesConst ? '' : 'const ';
  return '''
import 'package:bloc_test/bloc_test.dart';
import 'package:${n.package}/core/failures/offline_failure.dart';
import 'package:${n.package}/core/utils/bloc_status.dart';
import 'package:${n.package}/features/${n.f}/logic/cubit/${n.f}_cubit.dart';
import 'package:${n.package}/features/${n.f}/logic/cubit/${n.f}_state.dart';
import 'package:${n.package}/features/${n.f}/logic/failures/${n.f}_failure.dart';
import 'package:${n.package}/features/${n.f}/logic/models/responses/${n.m}_response.dart';
import 'package:${n.package}/features/${n.f}/logic/repositories/${n.f}_repository.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class Mock${n.fPascal}Repository extends Mock
    implements ${n.fPascal}Repository {}

void main() {
  late Mock${n.fPascal}Repository repository;

  // Sample generated from the feature spec.
  $kw sample = ${n.sampleCtor(1)};

  setUp(() {
    repository = Mock${n.fPascal}Repository();
  });

  group('load', () {
    blocTest<${n.fPascal}Cubit, ${n.fPascal}State>(
      'emits [loading, success] with items on Right',
      setUp: () {
        when(() => repository.${n.listOp.name}())
            .thenAnswer((_) async => ${c}Right([sample]));
      },
      build: () => ${n.fPascal}Cubit(repository),
      act: (cubit) => cubit.load(),
      expect: () => $c[
        $ec${n.fPascal}State(status: BlocStatus.loading),
        ${n.fPascal}State(status: BlocStatus.success, items: [sample]),
      ],
    );

    blocTest<${n.fPascal}Cubit, ${n.fPascal}State>(
      'emits [loading, failure] with the failure on Left',
      setUp: () {
        when(() => repository.${n.listOp.name}())
            .thenAnswer((_) async => const Left(${n.fPascal}LoadFailure()));
      },
      build: () => ${n.fPascal}Cubit(repository),
      act: (cubit) => cubit.load(),
      verify: (cubit) {
        expect(cubit.state.status, BlocStatus.failure);
        expect(cubit.state.error, isA<${n.fPascal}LoadFailure>());
      },
    );

    blocTest<${n.fPascal}Cubit, ${n.fPascal}State>(
      'transport failures pass through unchanged (wide seam)',
      setUp: () {
        when(() => repository.${n.listOp.name}())
            .thenAnswer((_) async => const Left(OfflineFailure()));
      },
      build: () => ${n.fPascal}Cubit(repository),
      act: (cubit) => cubit.load(),
      verify: (cubit) {
        expect(cubit.state.status, BlocStatus.failure);
        expect(cubit.state.error, isA<OfflineFailure>());
      },
    );

    blocTest<${n.fPascal}Cubit, ${n.fPascal}State>(
      'ignores a second load while one is in flight (double-fire guard)',
      setUp: () {
        when(() => repository.${n.listOp.name}())
            .thenAnswer((_) async => ${c}Right([sample]));
      },
      build: () => ${n.fPascal}Cubit(repository),
      act: (cubit) async {
        await Future.wait([cubit.load(), cubit.load()]);
      },
      verify: (_) {
        verify(() => repository.${n.listOp.name}()).called(1);
      },
    );
  });

${n.mutations.map((o) => '''

  group('${o.name}', () {
    blocTest<${n.fPascal}Cubit, ${n.fPascal}State>(
      'reloads the list on success',
      setUp: () {
        when(() => repository.${o.name}('1'))
            .thenAnswer((_) async => const Right(null));
        when(() => repository.${n.listOp.name}())
            .thenAnswer((_) async => ${n.samplesConst ? 'const ' : ''}Right([sample]));
      },
      build: () => ${n.fPascal}Cubit(repository),
      act: (cubit) => cubit.${o.name}('1'),
      verify: (_) {
        verify(() => repository.${o.name}('1')).called(1);
        verify(() => repository.${n.listOp.name}()).called(1);
      },
    );

    blocTest<${n.fPascal}Cubit, ${n.fPascal}State>(
      'emits the failure on Left and does NOT reload',
      setUp: () {
        when(() => repository.${o.name}('1'))
            .thenAnswer((_) async => const Left(${n.mutationFailureClass(o)}()));
      },
      build: () => ${n.fPascal}Cubit(repository),
      act: (cubit) => cubit.${o.name}('1'),
      verify: (cubit) {
        expect(cubit.state.error, isA<${n.mutationFailureClass(o)}>());
        verifyNever(() => repository.${n.listOp.name}());
      },
    );

    blocTest<${n.fPascal}Cubit, ${n.fPascal}State>(
      'transport failures pass through unchanged (wide seam)',
      setUp: () {
        when(() => repository.${o.name}('1'))
            .thenAnswer((_) async => const Left(OfflineFailure()));
      },
      build: () => ${n.fPascal}Cubit(repository),
      act: (cubit) => cubit.${o.name}('1'),
      verify: (cubit) {
        expect(cubit.state.error, isA<OfflineFailure>());
      },
    );

    blocTest<${n.fPascal}Cubit, ${n.fPascal}State>(
      'ignores a concurrent call while one is in flight',
      setUp: () {
        when(() => repository.${o.name}('1'))
            .thenAnswer((_) async => const Right(null));
        when(() => repository.${n.listOp.name}())
            .thenAnswer((_) async => ${n.samplesConst ? 'const ' : ''}Right([sample]));
      },
      build: () => ${n.fPascal}Cubit(repository),
      act: (cubit) async {
        await Future.wait([cubit.${o.name}('1'), cubit.${o.name}('1')]);
      },
      verify: (_) {
        verify(() => repository.${o.name}('1')).called(1);
      },
    );
  });''').join()}

  // Add tests here for every feature-specific operation you add to the cubit.
}
''';
}

String detailCubitTestT(Names n) {
  final kw = n.samplesConst ? 'const ' : 'final ';
  final c = n.samplesConst ? 'const ' : '';
  final ec = n.samplesConst ? '' : 'const ';
  return '''
import 'package:bloc_test/bloc_test.dart';
import 'package:${n.package}/core/utils/bloc_status.dart';
import 'package:${n.package}/features/${n.f}/logic/cubit/${n.m}_detail_cubit.dart';
import 'package:${n.package}/features/${n.f}/logic/cubit/${n.m}_detail_state.dart';
import 'package:${n.package}/features/${n.f}/logic/failures/${n.f}_failure.dart';
import 'package:${n.package}/features/${n.f}/logic/models/responses/${n.m}_response.dart';
import 'package:${n.package}/features/${n.f}/logic/repositories/${n.f}_repository.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class Mock${n.fPascal}Repository extends Mock
    implements ${n.fPascal}Repository {}

void main() {
  late Mock${n.fPascal}Repository repository;

  // Sample generated from the feature spec.
  $kw sample = ${n.sampleCtor(1)};

  setUp(() {
    repository = Mock${n.fPascal}Repository();
  });

  group('load', () {
    blocTest<${n.mPascal}DetailCubit, ${n.mPascal}DetailState>(
      'emits [loading, success] with the item on Right',
      setUp: () {
        when(() => repository.${n.singleOp!.name}('1'))
            .thenAnswer((_) async => ${c}Right(sample));
      },
      build: () => ${n.mPascal}DetailCubit(repository),
      act: (cubit) => cubit.load('1'),
      expect: () => $c[
        $ec${n.mPascal}DetailState(status: BlocStatus.loading),
        ${n.mPascal}DetailState(status: BlocStatus.success, item: sample),
      ],
    );

    blocTest<${n.mPascal}DetailCubit, ${n.mPascal}DetailState>(
      'emits [loading, failure] with the failure on Left',
      setUp: () {
        when(() => repository.${n.singleOp!.name}('1'))
            .thenAnswer((_) async => const Left(${n.fPascal}LoadFailure()));
      },
      build: () => ${n.mPascal}DetailCubit(repository),
      act: (cubit) => cubit.load('1'),
      verify: (cubit) {
        expect(cubit.state.status, BlocStatus.failure);
        expect(cubit.state.error, isA<${n.fPascal}LoadFailure>());
      },
    );
  });
}
''';
}

// ---------------------------------------------------------------------------
// anchored edits
// ---------------------------------------------------------------------------

void _editRoutes(
  Names n, {
  required List<String> edited,
  required List<String> warnings,
  required List<String> insertions,
}) {
  const path = 'lib/core/router/routes.dart';
  final file = File(path);
  if (!file.existsSync()) {
    warnings.add('$path not found — add the AppRoutes entries manually.');
    return;
  }
  var content = file.readAsStringSync();
  final wanted = <String>[
    "  ${n.fCamel}('${n.fPascal}', '/${n.fKebab}')",
    if (n.hasDetail)
      "  ${n.mCamel}Detail('${n.mPascal}Detail', '/${n.fKebab}/:id')",
  ]..removeWhere((e) => content.contains(e.trim().split("('").first + "('"));
  if (wanted.isEmpty) return;
  final entries = StringBuffer()..write(wanted.join(',\n'));
  final anchor = RegExp(r'\)\s*\n(\s*);');
  final match = anchor.firstMatch(content);
  if (match == null) {
    warnings.add('$path: enum terminator not found — add entries manually:\n'
        '$entries');
    return;
  }
  content = content.replaceRange(
    match.start,
    match.end,
    '),\n$entries\n${match.group(1)};',
  );
  file.writeAsStringSync(content);
  edited.add(path);
  insertions.add('    inserted into AppRoutes enum:\n'
      '$entries'.replaceAll(RegExp('^', multiLine: true), '    '));
}

void _editRouter(
  Names n, {
  required List<String> edited,
  required List<String> warnings,
  required List<String> insertions,
}) {
  const path = 'lib/core/router/router.dart';
  final file = File(path);
  if (!file.existsSync()) {
    warnings.add('$path not found — register the GoRoutes manually.');
    return;
  }
  var content = file.readAsStringSync();
  bool hasPage(String cls) => RegExp('\\b$cls\\(').hasMatch(content);
  final needList = !hasPage('${n.fPascal}Page');
  final needDetail = n.hasDetail && !hasPage('${n.mPascal}DetailPage');
  if (!needList && !needDetail) return;

  final pageImports = <String>[
    "import 'package:${n.package}/features/${n.f}/ui/pages/${n.f}_page.dart';",
    if (n.hasDetail)
      "import 'package:${n.package}/features/${n.f}/ui/pages/${n.m}_detail_page.dart';",
  ];
  final lines = content.split('\n');
  var importIdx = <int>[];
  void reindex() {
    importIdx = [
      for (var i = 0; i < lines.length; i++)
        if (lines[i].startsWith("import 'package:")) i,
    ];
  }

  reindex();
  if (importIdx.isEmpty) {
    warnings.add('$path: no package imports found — add imports manually.');
  } else {
    for (final imp in pageImports.reversed) {
      if (content.contains(imp) || lines.contains(imp)) continue;
      var insertAt = importIdx.last + 1;
      for (final i in importIdx) {
        if (imp.compareTo(lines[i]) < 0) {
          insertAt = i;
          break;
        }
      }
      lines.insert(insertAt, imp);
      reindex();
    }
    content = lines.join('\n');
  }

  final m = RegExp(r'routes:\s*\[\n').firstMatch(content);
  if (m == null) {
    warnings.add('$path: `routes: [` anchor not found — register GoRoutes '
        'manually.');
  } else {
    final goRoutes = StringBuffer();
    if (needList) goRoutes
      ..writeln('      // ${n.fPascal} (authenticated)')
      ..writeln('      GoRoute(')
      ..writeln('        name: AppRoutes.${n.fCamel}.name,')
      ..writeln('        path: AppRoutes.${n.fCamel}.path,')
      ..writeln('        pageBuilder: (context, state) => CupertinoPage(')
      ..writeln('          key: ValueKey(AppRoutes.${n.fCamel}.path),')
      ..writeln('          child: const ${n.fPascal}Page(),')
      ..writeln('        ),')
      ..writeln('      ),');
    if (needDetail) {
      goRoutes
        ..writeln('      GoRoute(')
        ..writeln('        name: AppRoutes.${n.mCamel}Detail.name,')
        ..writeln('        path: AppRoutes.${n.mCamel}Detail.path,')
        ..writeln('        pageBuilder: (context, state) => CupertinoPage(')
        ..writeln('          key: ValueKey(state.uri.toString()),')
        ..writeln('          child: ${n.mPascal}DetailPage(')
        ..writeln("            id: state.pathParameters['id'] ?? '',")
        ..writeln('          ),')
        ..writeln('        ),')
        ..writeln('      ),');
    }
    content = content.replaceRange(m.end, m.end, goRoutes.toString());
    insertions.add('    inserted GoRoutes: ${n.fCamel}'
        '${n.hasDetail ? ' + ${n.mCamel}Detail (:id param)' : ''} — house '
        'style (name/path from AppRoutes, CupertinoPage + ValueKey), page '
        'imports added alphabetically');
  }

  file.writeAsStringSync(content);
  edited.add(path);
}

void _editArbs(
  Names n, {
  required List<String> edited,
  required List<String> warnings,
  required List<String> nonEnglish,
  required List<String> insertions,
}) {
  var arbDir = 'lib/core/localization/arb';
  final l10n = File('l10n.yaml');
  if (l10n.existsSync()) {
    final m = RegExp(r'arb-dir:\s*(\S+)').firstMatch(l10n.readAsStringSync());
    if (m != null) arbDir = m.group(1)!;
  }
  final dir = Directory(arbDir);
  if (!dir.existsSync()) {
    warnings.add('$arbDir not found — add the localization keys manually.');
    return;
  }

  final title = n.fPascal.replaceAllMapped(
    RegExp('(?<=[a-z])(?=[A-Z])'),
    (_) => ' ',
  );
  final singularTitle = n.mPascal.replaceAllMapped(
    RegExp('(?<=[a-z])(?=[A-Z])'),
    (_) => ' ',
  );
  final words = n.f.replaceAll('_', ' ');
  final keys = <String, String>{
    '${n.fCamel}Title': title,
    '${n.fCamel}Empty': 'No $words yet',
    '${n.fCamel}ErrorGeneric': 'Something went wrong. Please try again.',
    '${n.fCamel}ErrorLoadFailed':
        "We couldn't load $words. Please try again.",
    if (n.hasDetail) '${n.fCamel}DetailTitle': singularTitle,
    for (final e in n.spec.errors)
      n.errorArbKey(e):
          '${_humanize(e.code)}. Please try again.',
    for (final o in n.mutations)
      n.mutationArbKey(o):
          "Couldn't ${n.mutationWords(o)}. Please try again.",
    for (final o in n.mutations.where((o) => o.confirm)) ...{
      '${n.fCamel}${o.pascal}ConfirmTitle':
          '${_humanize(_snake(o.name))}?',
      '${n.fCamel}${o.pascal}ConfirmBody': o.kind == 'delete'
          ? 'This cannot be undone.'
          : 'Are you sure?',
      '${n.fCamel}${o.pascal}ConfirmAction':
          _humanize(o.name.replaceAllMapped(
              RegExp('(?<=[a-z])(?=[A-Z])'), (_) => ' ').split(' ').first),
    },
    if (n.mutations.any((o) => o.confirm))
      '${n.fCamel}ConfirmCancel': 'Cancel',
  };
  final contexts = <String, String>{
    '${n.fCamel}Title': 'app bar title of the ${n.f} list page',
    '${n.fCamel}Empty': 'empty-state message on the ${n.f} list page',
    '${n.fCamel}ErrorGeneric': 'generic failure copy for this feature',
    '${n.fCamel}ErrorLoadFailed': 'copy when loading ${n.f} fails',
    if (n.hasDetail)
      '${n.fCamel}DetailTitle':
          'app bar title of the single-${n.m} detail page',
    for (final e in n.spec.errors)
      n.errorArbKey(e): 'failure copy for backend case `${e.code}`',
    for (final o in n.mutations)
      n.mutationArbKey(o): 'copy when the ${n.mutationWords(o)} action fails',
    for (final o in n.mutations.where((o) => o.confirm)) ...{
      '${n.fCamel}${o.pascal}ConfirmTitle':
          'confirmation dialog title before ${n.mutationWords(o)}',
      '${n.fCamel}${o.pascal}ConfirmBody':
          'confirmation dialog body text',
      '${n.fCamel}${o.pascal}ConfirmAction':
          'confirming button label in that dialog',
    },
    if (n.mutations.any((o) => o.confirm))
      '${n.fCamel}ConfirmCancel': 'cancel button label in confirm dialogs',
  };

  final arbFiles = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.arb'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  if (arbFiles.isEmpty) {
    warnings.add('no .arb files in $arbDir — add the keys manually.');
    return;
  }

  for (final f in arbFiles) {
    final isEnglish = f.path.contains('_en');
    final map = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    var changed = false;
    keys.forEach((key, value) {
      if (map.containsKey(key)) return;
      map[key] = value;
      changed = true;
      if (!isEnglish) {
        map['@$key'] = {
          'description': 'TODO(ai): translate — value is the English default',
        };
      }
    });
    if (changed) {
      f.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(map)}\n',
      );
      edited.add(f.path);
      if (!isEnglish) nonEnglish.add(f.path.split('/').last);
    }
  }
  insertions.add('    inserted ARB keys (into every .arb file): '
      '${keys.keys.join(', ')}');

  // i18n workfile: one Write fills every locale, the apply script merges it.
  final locales = <String>[];
  for (final f in arbFiles) {
    final m = RegExp(r'_([a-z]{2,3})\.arb$').firstMatch(f.path);
    if (m != null && m.group(1) != 'en') locales.add(m.group(1)!);
  }
  if (locales.isNotEmpty) {
    // Preserve already-filled translations across --force re-runs.
    final path = 'specs/${n.f}.i18n.json';
    var existing = const <String, dynamic>{};
    if (File(path).existsSync()) {
      try {
        existing =
            jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
      } on FormatException {
        existing = const {};
      }
    }
    String prior(String k, String l) {
      final e = existing[k];
      final v = e is Map<String, dynamic> ? e[l] : null;
      return v is String ? v : '';
    }

    final i18n = <String, dynamic>{
      for (final k in keys.keys)
        k: {
          'context': contexts[k] ?? '',
          'en': keys[k],
          for (final l in locales) l: prior(k, l),
        },
    };
    File(path).parent.createSync(recursive: true);
    File(path).writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(i18n)}\n');
    edited.add(path);
  }
}

String _humanize(String snakeCode) {
  final s = snakeCode.replaceAll('_', ' ');
  return s[0].toUpperCase() + s.substring(1);
}
