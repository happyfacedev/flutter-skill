// Subscriber cubit — receives typed refresh events via the
// `RefreshBusSubscriber<State>` mixin. Mixin auto-cancels subscriptions on
// close — no StreamSubscription field, no close() override.
//
// Identical in shape to cubit-creation's streaming_cubit.dart — kept here as
// a refresh-bus-focused example.

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:simple_refresh_bus/simple_refresh_bus.dart';
import 'package:your_app/core/events/refresh_events.dart';
import 'package:your_app/core/utils/bloc_status.dart';
import 'package:your_app/features/<feature>/logic/cubit/<feature>_state.dart';
import 'package:your_app/features/<feature>/logic/repositories/<feature>_repository.dart';

@injectable
class FeatureListCubit extends Cubit<FeatureListState>
    with RefreshBusSubscriber<FeatureListState> {
  FeatureListCubit(this._repository) : super(const FeatureListState()) {
    // One onData<T> per event type the cubit consumes.
    // Filter by payload INSIDE the callback when only a subset matters.
    onData<FeatureThingChanged>((event) {
      if (event.scopeId != _currentScopeId) return;
      unawaited(load());
    });

    // Zero-payload event — reload unconditionally.
    onData<FeatureListChanged>((_) => unawaited(load()));

    // Payload-carrying event — consume the pushed data directly, NO re-fetch.
    // The producer already holds the authoritative post-mutation value.
    onData<FeatureThingUpdated>((event) => emit(state.copyWith(
          status: BlocStatus.success,
          thing: event.thing,
        )));
  }

  final FeatureRepository _repository;

  // ⚠️ Placeholder — `null` here means the filter `event.scopeId != null` is
  // ALWAYS true and the subscriber never reloads. Wire the real scope source
  // (constructor-injected service, route param, etc.) before this file ships,
  // or delete the scope-filter callback above if you don't need it.
  String? get _currentScopeId =>
      throw UnimplementedError('Wire the real scope source here.');

  Future<void> load() async {
    emit(state.copyWith(status: BlocStatus.loading));

    final result = await _repository.fetchList();
    result.fold(
      (failure) {
        emit(state.copyWith(status: BlocStatus.failure, error: failure));
        addError(failure, StackTrace.current);
      },
      (items) => emit(state.copyWith(
        status: BlocStatus.success,
        items: items,
      )),
    );
  }
}
