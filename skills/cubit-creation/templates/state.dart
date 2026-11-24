// State class — Equatable + manual copyWith (NO Freezed for cubit states).
//
// Lives at:
//   lib/features/<feature>/logic/cubit/<feature>_state.dart
//
// `BlocStatus` enum (initial, loading, success, failure) is already defined in
// the project at lib/core/utils/bloc_status.dart — import, don't redefine.
//
// copyWith field forms:
//   - Persistent fields (status, data, ...): `field ?? this.field` — omitted fields keep their value.
//   - One-shot fields (error/failure — however named): direct assignment — any
//     emit that doesn't pass it clears it. Errors are single-use; never
//     `error ?? this.error`, never an explicit `error: null`.

import 'package:equatable/equatable.dart';
import 'package:your_app/core/utils/bloc_status.dart';
import 'package:simple_network_handler/simple_network_handler.dart'; // Failure base
// Or for Supabase projects:
// import 'package:simple_network_handler/simple_network_handler_supabase.dart';

class FeatureState extends Equatable {
  const FeatureState({
    this.status = BlocStatus.initial,
    this.error,
    this.data,
  });

  final BlocStatus status;
  final Failure? error;
  final FeatureData? data;     // your feature's payload type

  FeatureState copyWith({
    BlocStatus? status,
    Failure? error,
    FeatureData? data,
  }) {
    return FeatureState(
      status: status ?? this.status,
      error: error,                  // one-shot: cleared unless passed
      data: data ?? this.data,
    );
  }

  // EVERY field — a missing one is the classic "UI didn't update" bug.
  @override
  List<Object?> get props => [status, error, data];
}
