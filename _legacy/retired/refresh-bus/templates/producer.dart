// Producer cubit — fires refresh events on mutation success.
// Does NOT take a RefreshBus constructor parameter — the package is a singleton.

import 'package:bloc/bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:simple_refresh_bus/simple_refresh_bus.dart';
import 'package:your_app/core/events/refresh_events.dart';
import 'package:your_app/core/utils/bloc_status.dart';
import 'package:your_app/features/<feature>/logic/cubit/<feature>_state.dart';
import 'package:your_app/features/<feature>/logic/repositories/<feature>_repository.dart';

@injectable
class FeatureMutationCubit extends Cubit<FeatureMutationState> {
  FeatureMutationCubit(this._repository)
      : super(const FeatureMutationState());

  final FeatureRepository _repository;

  Future<void> doThing({required String thingId}) async {
    emit(state.copyWith(status: BlocStatus.loading));

    final result = await _repository.doThing(thingId: thingId);

    result.fold(
      (failure) {
        emit(state.copyWith(status: BlocStatus.failure, error: failure));
        addError(failure, StackTrace.current);
      },
      (_) {
        emit(state.copyWith(status: BlocStatus.success));

        // Push one event per affected concern — subscribers filter by type.
        // Subscribers that care about a specific scope then filter inside
        // their `onData<T>` callback by payload fields.
        RefreshBus.instance.push<FeatureThingChanged>(
          const FeatureThingChanged(thingId: 'replace-with-actual'),
        );
        RefreshBus.instance.push<FeatureListChanged>(
          const FeatureListChanged(),
        );
      },
    );
  }
}
