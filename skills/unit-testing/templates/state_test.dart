// Template: state test — copyWith preservation + one-shot error semantics.
// Replace your_app / Things / BlocStatus placeholders; the one-shot field may
// be named `error` or `failure` in the real state — rename consistently here.
// Cheap insurance on hand-written copyWith: catches dropped fields and
// sticky one-shot errors.

import 'package:flutter_test/flutter_test.dart';
import 'package:your_app/core/utils/bloc_status.dart';
import 'package:your_app/features/things/logic/cubit/things_cubit.dart';
import 'package:your_app/features/things/logic/failures/things_failure.dart';

import '../../../../helpers/helpers.dart'; // recompute ../ depth for your path

void main() {
  group('ThingsState', () {
    test('supports value equality', () {
      expect(const ThingsState(), const ThingsState());
    });

    test('copyWith preserves fields that are not passed', () {
      final populated = const ThingsState().copyWith(
        status: BlocStatus.success,
        things: [buildThing()],
      );

      final copied = populated.copyWith(status: BlocStatus.loading);

      expect(copied.things, populated.things); // untouched field preserved
      expect(copied.status, BlocStatus.loading);
    });

    // One-shot error convention (cubit-creation Critical Rule 4, in full):
    // the one-shot field is assigned DIRECTLY in copyWith (`error: error`) —
    // never `?? this.error`, no sentinel parameters, and callers never pass
    // an explicit `null` (omitting it already clears). These two tests are
    // the regression guard for the sticky-error defect class — if the second
    // one fails against real source, the source violates the rule (sentinel
    // or `?? this.error` copyWith, often with compensating `error: null` at
    // cubit call sites): report it, apply the rule-mandated fix on BOTH the
    // state and any compensating call sites — don't bend the test.
    test('copyWith(error: x) sets the one-shot error', () {
      final state = const ThingsState().copyWith(
        status: BlocStatus.failure,
        error: const ThingsLoadFailure(),
      );

      expect(state.error, const ThingsLoadFailure());
    });

    test('a copyWith without error clears it (one-shot, not sticky)', () {
      final failed = const ThingsState().copyWith(
        status: BlocStatus.failure,
        error: const ThingsLoadFailure(),
      );

      final next = failed.copyWith(status: BlocStatus.loading);

      expect(next.error, isNull);
    });
  });
}
