// State class — manual copyWith (NO Freezed for cubit states).
//
// Lives at:
//   lib/features/<feature>/logic/cubit/<feature>_state.dart
//
// `BlocStatus` enum (initial, loading, success, failure) is already defined in
// the project at lib/core/utils/bloc_status.dart — import, don't redefine.

import 'package:your_app/core/utils/bloc_status.dart';
import 'package:simple_network_handler/simple_network_handler.dart'; // Failure base
// Or for Supabase projects:
// import 'package:simple_network_handler/simple_network_handler_supabase.dart';

class FeatureState {
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
      error: error ?? this.error,
      data: data ?? this.data,
    );
  }
}
