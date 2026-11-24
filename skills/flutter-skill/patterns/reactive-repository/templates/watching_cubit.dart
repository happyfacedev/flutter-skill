// Watching cubit — subscribes to a reactive repository stream for data and
// keeps errors on the request path.
//
// Lives at:
//   lib/features/<feature>/logic/cubit/<feature>_cubit.dart

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:your_app/core/utils/bloc_status.dart';
import 'package:your_app/core/utils/stream_subscriber.dart';
import 'package:your_app/features/<feature>/logic/cubit/<feature>_state.dart';
import 'package:your_app/features/<feature>/logic/repositories/things_repository.dart';

@injectable
class ThingsListCubit extends Cubit<ThingsListState>
    with StreamSubscriber<ThingsListState> {
  ThingsListCubit(this._repository) : super(const ThingsListState()) {
    // Data arrives here — from this cubit's own load, from any other flow's
    // mutation, or replayed from the cache for a late-created cubit.
    subscribe(_repository.watchThings(), (things) {
      emit(state.copyWith(status: BlocStatus.success, things: things));
    });
  }

  final ThingsRepository _repository;

  /// Triggers the fetch; the RESULT arrives via the subscription above.
  /// Only the failure path emits here.
  Future<void> load() async {
    emit(state.copyWith(status: BlocStatus.loading));

    final result = await _repository.loadThings();
    if (isClosed) return;
    result.fold(
      (failure) {
        emit(state.copyWith(status: BlocStatus.failure, error: failure));
        addError(failure, StackTrace.current);
      },
      (_) {
        // Success is a no-op: the pushed value already reached the
        // subscription and emitted BlocStatus.success with the data.
      },
    );
  }
}
