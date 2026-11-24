// Unified verification gate — ONE command, ONE compact PASS/FAIL block.
//
// Usage (from the repo root):
//   dart run <path-to>/verify_feature.dart
//
// Runs, in order:
//   1. flutter gen-l10n
//   2. build_runner — only if a non-generated .dart file newer than the
//      newest generated output carries a codegen annotation
//   3. flutter analyze — every issue classified IN SCOPE (files this change
//      created/modified per git status) vs PRE-EXISTING (untouched files)
//   4. flutter test — CR-safe, failures-only output
//   5. TODO(ai) grep over lib/ and test/
//   6. project checkers if present (feature isolation, widgetbook coverage)
//   7. ARB parity (same key set everywhere) + identical-to-English warnings
//
// Exit code 0 = PASS. Analyzer errors fail anywhere; warnings and infos fail
// only in scope.

import 'dart:convert';
import 'dart:io';

final _fails = <String>[];
final _warns = <String>[];
final _oks = <String>[];

void main(List<String> args) {
  if (!File('pubspec.yaml').existsSync()) {
    stderr.writeln('ERROR: run from the repo root.');
    exit(66);
  }

  _genL10n();
  _buildRunnerIfNeeded();
  _analyze();
  _test();
  _todoGrep();
  _projectCheckers();
  _arbParity();

  final pass = _fails.isEmpty;
  stdout.writeln('\n===== GATE ${pass ? 'PASS' : 'FAIL'} =====');
  for (final o in _oks) {
    stdout.writeln('  ok   $o');
  }
  for (final w in _warns) {
    stdout.writeln('  warn $w');
  }
  for (final f in _fails) {
    stdout.writeln('  FAIL $f');
  }
  if (pass) {
    stdout.writeln('All in-scope checks green. Pre-existing issues (if any '
        'listed as warn) are not yours to fix.');
  } else {
    stdout.writeln('Fix every FAIL above, then re-run this gate.');
  }
  exit(pass ? 0 : 1);
}

ProcessResult _run(String exe, List<String> a) => Process.runSync(exe, a);

void _genL10n() {
  if (!File('l10n.yaml').existsSync()) return;
  final r = _run('flutter', ['gen-l10n']);
  r.exitCode == 0
      ? _oks.add('gen-l10n')
      : _fails.add('gen-l10n: ${_tail(r, 3)}');
}

void _buildRunnerIfNeeded() {
  var newestGen = DateTime.fromMillisecondsSinceEpoch(0);
  var newestAnnotated = DateTime.fromMillisecondsSinceEpoch(0);
  final annotation = RegExp(
      r'@(?:\w+\.)?(freezed|injectable|Injectable|lazySingleton|LazySingleton|singleton|Singleton|UseCase|RestApi|JsonSerializable)\b');
  for (final f in Directory('lib').listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.dart')) continue;
    final stat = f.statSync();
    if (f.path.endsWith('.g.dart') || f.path.endsWith('.freezed.dart') ||
        f.path.endsWith('.gen.dart') || f.path.contains('.directories.g')) {
      if (stat.modified.isAfter(newestGen)) newestGen = stat.modified;
    } else if (stat.modified.isAfter(newestAnnotated)) {
      try {
        if (annotation.hasMatch(f.readAsStringSync())) {
          newestAnnotated = stat.modified;
        }
      } on FileSystemException {
        continue;
      }
    }
  }
  if (!newestAnnotated.isAfter(newestGen)) {
    _oks.add('build_runner (skipped — generated outputs up to date)');
    return;
  }
  final r = _run('dart',
      ['run', 'build_runner', 'build', '--delete-conflicting-outputs']);
  if (r.exitCode == 0) {
    _oks.add('build_runner');
    if (File('tools/fix_part_directives.dart').existsSync()) {
      _run('dart', ['tools/fix_part_directives.dart']);
    }
  } else {
    _fails.add('build_runner: ${_tail(r, 5)}');
  }
}

Set<String> _changedFiles() {
  final files = <String>{};
  // Union with scaffold manifests: scope survives dirty trees and commits.
  final specs = Directory('specs');
  if (specs.existsSync()) {
    for (final f in specs.listSync().whereType<File>()) {
      if (!f.path.endsWith('.manifest.json')) continue;
      try {
        final m = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        for (final k in ['created', 'edited']) {
          files.addAll(((m[k] as List?) ?? const []).cast<String>());
        }
      } on FormatException {
        continue;
      }
    }
  }
  final r = _run('git', ['status', '--porcelain']);
  if (r.exitCode != 0) return files;
  for (final line in (r.stdout as String).split('\n')) {
    if (line.length < 4) continue;
    var p = line.substring(3).trim();
    if (p.contains(' -> ')) p = p.split(' -> ').last;
    if (p.endsWith('/')) {
      // Strip the slash: Directory('x/').listSync yields 'x//file' paths
      // that never match analyzer output — silently unscoping new dirs.
      final d = Directory(p.substring(0, p.length - 1));
      if (d.existsSync()) {
        for (final f in d.listSync(recursive: true)) {
          if (f is File) files.add(f.path);
        }
      }
    } else {
      files.add(p);
    }
  }
  return files;
}

void _analyze() {
  final r = _run('flutter', ['analyze', 'lib', 'test']);
  final summary = RegExp(r'(\d+) issues? found')
      .firstMatch(r.stdout as String);
  final changed = _changedFiles();
  final inScope = <String>[];
  var preExisting = 0;
  for (final line in (r.stdout as String).split('\n')) {
    final m = RegExp(r'(info|warning|error) .*? ((?:lib|test)/[^\s:]+):\d+')
        .firstMatch(line);
    if (m == null) continue;
    // An error fails wherever it is: a change here can break an untouched file.
    m.group(1) == 'error' || changed.contains(m.group(2))
        ? inScope.add(line.trim())
        : preExisting++;
  }
  final parsed = inScope.length + preExisting;
  final reported = int.tryParse(summary?.group(1) ?? '') ?? 0;
  if (parsed < reported || (r.exitCode != 0 && parsed == 0)) {
    _fails.add('analyze: exited ${r.exitCode}, reported $reported issue(s) but '
        'only $parsed were parsed — run flutter analyze manually.');
    return;
  }
  if (inScope.isEmpty) {
    _oks.add('analyze (0 in-scope issues'
        '${preExisting > 0 ? '; $preExisting pre-existing in untouched files — not yours' : ''})');
  } else {
    for (final i in inScope.take(10)) {
      _fails.add('analyze: $i');
    }
    if (inScope.length > 10) {
      _fails.add('analyze: ...and ${inScope.length - 10} more in-scope issues');
    }
  }
}

void _test() {
  final r = _run('flutter', ['test']);
  final out = (r.stdout as String).replaceAll('\r', '\n');
  final lines = out.split('\n').where((l) => l.trim().isNotEmpty).toList();
  final last = lines.isEmpty ? '' : lines.last;
  if (r.exitCode == 0 && last.contains('All tests passed')) {
    final m = RegExp(r'\+(\d+)').allMatches(last).lastOrNull;
    _oks.add('tests (${m != null ? '${m.group(1)} passed' : 'all passed'})');
  } else {
    var reported = 0;
    for (var i = 0; i < lines.length && reported < 6; i++) {
      if (!lines[i].contains('[E]')) continue;
      reported++;
      _fails.add('test: ${lines[i].trim()}');
      // The lines right after [E] carry the actual error/compile message.
      for (final ctx in lines.skip(i + 1).take(4)) {
        if (ctx.contains('[E]') || ctx.trim().startsWith('00:')) break;
        _fails.add('        ${ctx.trim()}');
      }
    }
    if (reported == 0) _fails.add('test: suite failed — ${_tailStr(out, 3)}');
  }
}

void _todoGrep() {
  final hits = <String>[];
  for (final dir in ['lib', 'test']) {
    final d = Directory(dir);
    if (!d.existsSync()) continue;
    for (final f in d.listSync(recursive: true)) {
      if (f is! File) continue;
      if (!(f.path.endsWith('.dart') || f.path.endsWith('.arb'))) continue;
      // Generated files only echo markers from their sources — skip them.
      if (f.path.contains('/generated/') ||
          f.path.endsWith('.g.dart') ||
          f.path.endsWith('.freezed.dart')) {
        continue;
      }
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('TODO(ai)')) hits.add('${f.path}:${i + 1}');
      }
    }
  }
  hits.isEmpty
      ? _oks.add('no TODO(ai) leftovers')
      : _fails.addAll(hits.take(8).map((h) => 'TODO(ai) remains: $h'));
}

void _projectCheckers() {
  for (final entry in const [
    ('tools/check_feature_isolation.dart', 'feature isolation'),
    ('tools/check_widgetbook_coverage.dart', 'widgetbook coverage'),
    ('tools/check_ui_conventions.dart', 'UI conventions'),
  ]) {
    if (!File(entry.$1).existsSync()) continue;
    final r = _run('dart', [entry.$1]);
    r.exitCode == 0
        ? _oks.add(entry.$2)
        : _fails.add('${entry.$2}: ${_tail(r, 3)}');
  }
}

void _arbParity() {
  var arbDir = 'lib/core/localization/arb';
  final l10n = File('l10n.yaml');
  if (l10n.existsSync()) {
    final m = RegExp(r'arb-dir:\s*(\S+)').firstMatch(l10n.readAsStringSync());
    if (m != null) arbDir = m.group(1)!;
  }
  final dir = Directory(arbDir);
  if (!dir.existsSync()) return;
  final maps = <String, Map<String, dynamic>>{};
  for (final f in dir.listSync().whereType<File>()) {
    if (!f.path.endsWith('.arb')) continue;
    try {
      maps[f.path.split('/').last] =
          jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    } on FormatException {
      _fails.add('arb: ${f.path} is not valid JSON');
      return;
    }
  }
  if (maps.length < 2) return;
  Set<String> keysOf(Map<String, dynamic> m) =>
      m.keys.where((k) => !k.startsWith('@')).toSet();
  final all = maps.values.map(keysOf).reduce((a, b) => a.union(b));
  var parityOk = true;
  maps.forEach((name, m) {
    final missing = all.difference(keysOf(m));
    if (missing.isNotEmpty) {
      parityOk = false;
      _fails.add('arb parity: $name missing ${missing.take(6).join(', ')}'
          '${missing.length > 6 ? ' (+${missing.length - 6})' : ''}');
    }
  });
  if (parityOk) _oks.add('arb parity (${all.length} keys × ${maps.length} locales)');

  final enEntry = maps.entries
      .where((e) => e.key.contains('_en'))
      .map((e) => e.value)
      .toList();
  if (enEntry.isEmpty) return;
  final en = enEntry.first;
  // Scope to keys this change introduced (from specs/*.i18n.json) when
  // present — pre-existing untranslated keys are not this change's problem.
  final ourKeys = <String>{};
  final specsDir = Directory('specs');
  if (specsDir.existsSync()) {
    for (final f in specsDir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.i18n.json')) continue;
      try {
        ourKeys.addAll(
            (jsonDecode(f.readAsStringSync()) as Map<String, dynamic>).keys);
      } on FormatException {
        continue;
      }
    }
  }
  maps.forEach((name, m) {
    if (name.contains('_en')) return;
    final identical = keysOf(m)
        .where((k) =>
            m[k] is String &&
            m[k] == en[k] &&
            (ourKeys.isEmpty || ourKeys.contains(k)))
        .toList();
    if (identical.isNotEmpty) {
      _warns.add('$name: ${identical.length} value(s) identical to English '
          '(untranslated or legitimately identical — check: '
          '${identical.take(5).join(', ')})');
    }
  });
}

String _tail(ProcessResult r, int n) {
  final s = (r.stderr.toString().trim().isEmpty ? r.stdout : r.stderr)
      .toString();
  return _tailStr(s, n);
}

String _tailStr(String s, int n) {
  final lines =
      s.replaceAll('\r', '\n').split('\n').where((l) => l.trim().isNotEmpty);
  return lines.skip(lines.length > n ? lines.length - n : 0).join(' | ');
}

extension<T> on Iterable<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
