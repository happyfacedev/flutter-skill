// Applies a filled specs/<feature>.i18n.json to every .arb file, removes the
// TODO(ai) @-descriptions the scaffolder stamped, and re-runs gen-l10n.
//
// Usage (from the repo root, after filling every empty locale slot):
//   dart run <path-to>/apply_translations.dart specs/<feature>.i18n.json
//
// The i18n file shape (written by the scaffolder):
//   { "<key>": { "context": "...", "en": "English value", "ro": "" }, ... }
// Every non-"context" slot must be non-empty before applying — the script
// reports ALL empty slots at once and applies nothing until they are filled.

import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  if (args.length != 1 || !File(args.first).existsSync()) {
    stderr.writeln(
        'Usage: dart run apply_translations.dart specs/<feature>.i18n.json');
    exit(64);
  }
  final i18n =
      jsonDecode(File(args.first).readAsStringSync()) as Map<String, dynamic>;

  final empty = <String>[];
  i18n.forEach((key, v) {
    (v as Map<String, dynamic>).forEach((locale, value) {
      if (locale == 'context') return;
      if (value is! String || value.trim().isEmpty) {
        empty.add('$key.$locale');
      }
    });
  });
  if (empty.isNotEmpty) {
    stderr.writeln('NOT APPLIED — fill ALL empty slots first:');
    for (final e in empty) {
      stderr.writeln('  - $e');
    }
    exit(65);
  }

  var arbDir = 'lib/core/localization/arb';
  final l10n = File('l10n.yaml');
  if (l10n.existsSync()) {
    final m = RegExp(r'arb-dir:\s*(\S+)').firstMatch(l10n.readAsStringSync());
    if (m != null) arbDir = m.group(1)!;
  }

  final applied = <String>[];
  for (final f in Directory(arbDir).listSync().whereType<File>()) {
    if (!f.path.endsWith('.arb')) continue;
    final localeMatch =
        RegExp(r'_([a-z]{2,3}(?:_[A-Za-z0-9]{2,8})*)\.arb$').firstMatch(f.path);
    if (localeMatch == null) continue;
    final locale = localeMatch.group(1)!;
    final map = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    var changed = false;
    i18n.forEach((key, v) {
      final value = (v as Map<String, dynamic>)[locale];
      if (value is! String) return;
      if (map[key] != value) {
        map[key] = value;
        changed = true;
      }
      if (map.remove('@$key') != null) changed = true;
    });
    if (changed) {
      f.writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(map)}\n');
      applied.add(f.path.split('/').last);
    }
  }

  final r = Process.runSync('flutter', ['gen-l10n']);
  stdout.writeln('Applied to: ${applied.join(', ')}. gen-l10n: '
      '${r.exitCode == 0 ? 'ok' : 'FAILED — run flutter gen-l10n manually'}');
  if (r.exitCode != 0) exit(1);
}
