// Single-slot pending-intent buffer. The router calls set() when a tap
// arrives before the navigator is ready (cold-start, mid-auth, mid-modal);
// a listener (typically wired in the post-auth pipeline) reads the slot
// and routes when ready.
//
// CRITICAL — NavigationIntent MUST override == / hashCode (see
// notification_router.dart). ValueNotifier uses != to decide whether to
// fire listeners. Without proper equality, "same intent set twice" either
// double-fires or never fires depending on identity ordering.
//
// Recommended TTL: drop a buffered intent after ~5 minutes (the pain
// points section in reference.md §12 cites forever-buffered intent as a
// production footgun). The template leaves the TTL to the project — most
// projects clear on user-logout transitions anyway.
//
// PROJECT SUBSTITUTIONS: none.

import 'package:flutter/foundation.dart';

import 'package:<your_app>/core/notifications/notification_router.dart';

class PendingIntentStore {
  final ValueNotifier<NavigationIntent?> _slot = ValueNotifier(null);

  ValueListenable<NavigationIntent?> get listenable => _slot;
  NavigationIntent? get current => _slot.value;

  // Newest wins; replaces any prior buffered intent.
  void set(NavigationIntent intent) => _slot.value = intent;

  // Atomically read-and-clear. The caller (e.g. the post-auth pipeline)
  // calls this once the navigator is ready and the user has cleared all
  // gating modals.
  NavigationIntent? take() {
    final value = _slot.value;
    _slot.value = null;
    return value;
  }

  void clear() => _slot.value = null;
}
