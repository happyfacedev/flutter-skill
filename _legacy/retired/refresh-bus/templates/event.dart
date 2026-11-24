// Refresh bus event class. Append to lib/core/events/refresh_events.dart.
//
// Conventions:
//   - `final class` (no subclassing)
//   - `const` constructor (zero-payload events reuse the singleton instance)
//   - Named past-tense + noun: `ItemsChanged`, `OrderSubmitted`,
//     `UserOrganizationsChanged` — NOT imperative ("RefreshItems")
//   - Payload fields are the minimum identifiers a subscriber needs to
//     decide whether to react

/// Emitted when <thing> mutated. Subscribers filter by [<field>] when they
/// only care about a subset.
final class FeatureThingChanged {
  const FeatureThingChanged({
    required this.scopeId,
    required this.thingId,
  });

  final String scopeId;
  final String thingId;
}

/// Zero-payload variant — subscribers reload unconditionally because the
/// affected dataset is small / cheap to refetch.
final class FeatureListChanged {
  const FeatureListChanged();
}
