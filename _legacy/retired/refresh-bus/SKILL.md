---
name: refresh-bus
description: Internal flutter-skill pattern — invoked via the flutter-skill router, not from this description. (Cross-cubit refresh events.)
---

# Refresh Bus

The `simple_refresh_bus` package is the project's canonical way to signal cross-cubit data invalidation without injecting one cubit into another. A producer cubit `push`es a typed event when its mutation invalidates data elsewhere; one or more subscriber cubits receive the typed payload via the `RefreshBusSubscriber` mixin and reload.

This is the substitute for the forbidden cubit-to-cubit dependency (see `cubit-creation` Critical Rule 5). Mutations stay local; refreshes happen on demand at the subscriber.

## When to use it

**Use the refresh bus when:**
- A mutation in cubit A (e.g. `leaveOrganization()`) invalidates data displayed by cubit B (e.g. the user's organization list)
- Multiple cubits should react to the same event (e.g. `OrganizationChanged` triggers reloads in both the home page and a header widget when the active tenant switches)
- **A mutation already holds the fresh data other cubits display — push it as the event payload so subscribers update WITHOUT re-fetching.** E.g. `EditProfileCubit` saves and pushes `ProfileUpdated(profile)`; `ProfileCubit` emits the payload straight into its state. *Why:* the producer just received the authoritative post-mutation value from the backend; a subscriber re-fetch is a redundant request for data already in hand. Reserve reload-on-event for cases where the payload can't carry what the subscriber needs (filtered lists, aggregates).

**Don't use the refresh bus for:**
- Navigation events (use the router / pending navigation store)
- Data the receiver can compute from its own state (just update the receiver's state)
- Tight coordination between two cubits on the SAME page (use a parent widget `BlocListener`) — cross-page or cross-feature propagation belongs on the bus, since no shared parent widget exists
- Auth state, theme, or other singletons (those have their own cubits already in DI)

## The event surface

Cross-feature event classes live in `lib/core/events/refresh_events.dart`. They are **plain classes** (not a sealed hierarchy — the package discriminates by type parameter `T`, not by `is` checks). Each event class carries the minimum a subscriber needs: identifier(s) to decide whether the event applies, or the updated entity itself when subscribers should consume the new data without re-fetching.

Currently defined events:
- `OrganizationChanged({organizationId})` — the active organization (tenant) was switched; carries the new `organizationId` (already published to `OrganizationContext`). Session-scoped cubits reload against the new tenant.
- `UserOrganizationsChanged()` — the set of organizations the user belongs to changed (join / leave); no payload, subscribers reload unconditionally.

Add your own events alongside these as features grow. The examples below use an illustrative `ItemsChanged({organizationId})` — a scoped event you might add for a feature that owns a collection of items. Adding a new event is one of the two main tasks this skill handles — see the workflow below.

## Critical Rules

1. **Event classes are plain classes — `final class` with `const` constructors.** *Why:* `RefreshBus.instance.push<T>(value)` discriminates by `T` (the type parameter). A sealed hierarchy adds no value and forces a redundant `switch` at the subscriber side. `final` prevents accidental subclassing; `const` lets producers reuse instances for zero-payload events.

2. **Producers use `RefreshBus.instance.push<EventType>(event)`** — not `_refreshBus.emit(...)` (that was the old local API). *Why:* the package is a singleton; constructor injection is no longer needed for the bus itself. Removing the `_refreshBus` field shrinks the cubit's constructor.

3. **Subscribers use the `RefreshBusSubscriber<State>` mixin + `onData<T>(callback)` in the constructor.** *Why:* the mixin tracks subscriptions and cancels them when the cubit closes — no `StreamSubscription` field, no `close()` override needed. The typed `onData<T>` removes the `is` check.

4. **Filter by payload fields inside the callback when needed.** *Why:* `onData<ItemsChanged>` fires for every `ItemsChanged` event regardless of `organizationId`. Subscribers that only care about the current scope check inside the callback: `if (event.organizationId != _scope.currentOrganizationId) return;`. Filtering by type happens automatically; filtering by payload is the cubit's responsibility.

5. **Push one event per affected concern, not one event per mutation.** *Why:* a mutation can invalidate more than one surface — e.g. archiving an item might invalidate the item detail page (`ItemChanged`), the items list (`ItemsChanged`), and a summary widget. Push one event per concern — each subscriber filters by its own type. A single "everything changed" event would force every subscriber to reload regardless of relevance.

## Templates

- [Producer cubit](templates/producer.dart) — fires events on mutation success
- [Subscriber cubit](templates/subscriber.dart) — uses the mixin + `onData<T>` (the `cubit-creation` skill's `streaming_cubit.dart` is the same pattern, focused on cubit shape; this template is focused on event wiring)
- [Event class](templates/event.dart) — the `final class` shape for new events

> **Placeholder note**: templates use `package:your_app/...` and `<feature>` as placeholders. Find-and-replace `your_app` → the project's package name and `<feature>` → your feature name before pasting.

## Reference

See [reference.md](reference.md) for:
- Producer side: `push<T>` vs `refresh<T>` (when to use which)
- Subscriber side: lifecycle, multiple events, payload filtering
- Adding a new event: where it goes, who has to import it, naming convention
- Migrating from a custom event bus
- Testing cubits that use the bus
- Common mistakes

## Checklist

- [ ] Event class is a `final class` with `const` constructor, lives in `lib/core/events/refresh_events.dart`
- [ ] Producer cubit DOES NOT take a `RefreshBus` constructor parameter — uses `RefreshBus.instance.push<EventType>(event)` directly
- [ ] Subscriber cubit declares `with RefreshBusSubscriber<XxxState>` on the class
- [ ] Subscriber calls `onData<EventType>(callback)` in the constructor body (one per event type it consumes)
- [ ] Subscriber callbacks wrap async work in `unawaited(...)` — the listener signature is sync
- [ ] Payload filtering (e.g. `event.organizationId == _scope.currentOrganizationId`) is inside the callback, not before
- [ ] No `StreamSubscription` field, no `close()` override added just for refresh-bus cleanup
- [ ] If a mutation invalidates multiple concerns, multiple events are pushed (one per concern)
- [ ] New event classes named in past-tense plus the noun they affect (`ItemsChanged`, not `RefreshItems`)
