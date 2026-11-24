// Template: test/helpers/fixtures.dart — fixture loaders for repository-Impl
// mapping tests. Fixtures live at test/fixtures/<feature>/<name>.json and stay
// byte-identical to real backend responses — that is the point of the test.
// Paths resolve from the package root (flutter test's working directory).

import 'dart:convert';
import 'dart:io';

String fixture(String path) => File('test/fixtures/$path').readAsStringSync();

dynamic fixtureJson(String path) => jsonDecode(fixture(path));
