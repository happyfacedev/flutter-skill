// Streaming cubit — subscribes to `simple_refresh_bus` events via the
// `RefreshBusSubscriber` mixin. The mixin handles subscription cleanup
// automatically — no `close()` override or `StreamSubscription` field.
//
// Use for cubits that need to react to events fired by other cubits:
//   - Cross-feature data invalidation (`OrganizationChanged`, `UserOrganizationsChanged`)
//   - Multi-listener notifications
//
// For cubits that subscribe to non-refresh-bus streams (FCM, auth state,
// connectivity), keep the manual StreamSubscription + close() pattern instead.
//
// Lives at:
//   lib/features/<feature>/logic/cubit/<feature>_cubit.dart

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:simple_refresh_bus/simple_refresh_bus.dart';
import 'package:your_app/core/events/refresh_events.dart';
import 'package:your_app/core/utils/bloc_status.dart';
import 'package:your_app/features/<feature>/logic/cubit/<feature>_state.dart';
import 'package:your_app/features/<feature>/logic/repositories/<feature>_repository.dart';

@injectable
class FeatureCubit extends Cubit<FeatureState>
    with RefreshBusSubscriber<FeatureState> {
  FeatureCubit(this._repository) : super(const FeatureState()) {
    // Subscribe to typed events in the constructor. The mixin tracks the
    // subscription and cancels it when the cubit closes — no manual cleanup.
    // `unawaited(...)` because the listener signature is sync; the reload
    // runs in the background.
    onData<UserOrganizationsChanged>((_) => unawaited(loadData()));

    // Multiple events: one onData<T> per type.
    onData<OrganizationChanged>((event) {
      // Filter by payload fields when the cubit only cares about a subset.
      if (event.organizationId != _currentOrganizationId) return;
      unawaited(loadData());
    });
  }

  final FeatureRepository _repository;

  // Replace with real organization source (route param, context, etc.) if needed.
  String? get _currentOrganizationId => null;

  Future<void> loadData() async {
    emit(state.copyWith(status: BlocStatus.loading));

    final result = await _repository.fetchThing();
    result.fold(
      (failure) {
        emit(state.copyWith(status: BlocStatus.failure, error: failure));
        addError(failure, StackTrace.current);
      },
      (data) => emit(state.copyWith(
        status: BlocStatus.success,
        data: data,
      )),
    );
  }
}
