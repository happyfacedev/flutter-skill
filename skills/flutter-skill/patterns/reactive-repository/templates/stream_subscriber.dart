// StreamSubscriber — subscription lifecycle for cubits that watch repository
// streams. Create once per project at:
//   lib/core/utils/stream_subscriber.dart

import 'dart:async';

import 'package:bloc/bloc.dart';

/// Tracks stream subscriptions made in a cubit's constructor and cancels
/// them when the cubit closes — no `StreamSubscription` fields, no manual
/// `close()` override in the cubit.
///
/// If the cubit overrides `close()` for other cleanup, call `super.close()`
/// last — that's where subscriptions are cancelled.
mixin StreamSubscriber<State> on BlocBase<State> {
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  /// Subscribe to [stream]; the subscription is cancelled automatically on
  /// [close]. The callback should only `emit` — no async work inside it.
  void subscribe<T>(Stream<T> stream, void Function(T data) onData) {
    _subscriptions.add(stream.listen(onData));
  }

  @override
  Future<void> close() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    return super.close();
  }
}
