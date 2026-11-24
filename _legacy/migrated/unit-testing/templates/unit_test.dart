// Plain unit test for pure Dart logic — parsers, formatters, utilities,
// pure value objects. No bloc_test, no mocktail (unless mocking is needed).

import 'package:flutter_test/flutter_test.dart';
import 'package:your_app/core/utils/<thing>.dart';

void main() {
  group('<Thing>', () {
    test('returns expected value for typical input', () {
      expect(parseThing('input'), equals('expected'));
    });

    test('returns null for empty input', () {
      expect(parseThing(''), isNull);
    });

    test('throws on malformed input', () {
      expect(
        () => parseThing('!!!'),
        throwsA(isA<FormatException>()),
      );
    });

    // For multi-case behaviors, parameterize:
    for (final entry in <String, String>{
      'a': 'A',
      'ab': 'AB',
      'abc': 'ABC',
    }.entries) {
      test('uppercases ${entry.key}', () {
        expect(upperCase(entry.key), equals(entry.value));
      });
    }
  });
}
