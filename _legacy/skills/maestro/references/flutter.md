# Flutter-specific Maestro reference

Load when writing flows for a Flutter app (iOS simulator or Android emulator). Flutter has several quirks that will bite you if you treat it like a native app.

## The attribute map

Every Flutter widget produces a hierarchy node with these attributes (visible via `maestro hierarchy`). Here's how Flutter maps onto Maestro's world:

| Attribute          | Native iOS source           | Native Android source        | Flutter source                                               |
|--------------------|-----------------------------|------------------------------|--------------------------------------------------------------|
| `text`             | UILabel / UITextField       | TextView / EditText          | **Empty for app `Text` widgets.** TextField's live value DOES go here. (iOS SystemUI is the other source.) |
| `accessibilityText`| `accessibilityLabel`        | `contentDescription`         | `Text` widget content, `Semantics(label:)`, merged children  |
| `resource-id`      | `accessibilityIdentifier`   | `android:id` / testTag       | `Semantics(identifier: '...')`                               |
| `hintText`         | placeholder                 | `android:hint`               | `TextField(hintText: ...)`                                   |

## Gotcha #1 — `text` attribute is empty for Flutter `Text` widgets

Flutter's `Text('...')` widget does not populate the `text` attribute — its content ends up in `accessibilityText`. `TextField` / `TextFormField` **do** populate `text` with their live input value (useful for input-state assertions).

```
# Text('Welcome') widget                           # TextField with controller.text = "hello@test.com"
{                                                  {
  "accessibilityText": "Welcome",                    "text": "hello@test.com",
  "text": "",                                        "accessibilityText": "...",
  "resource-id": ""                                  "resource-id": "..."
}                                                  }
```

Consequences:

- **`copyTextFrom: id: "foo"` returns `undefined`** when `foo` is a `Semantics(identifier:)` wrapping a `Text`. Maestro reads the `text` field, which is empty on Flutter Text widgets.
- `copyTextFrom` **does work on a `TextField`** — you can capture its live input value.
- For a non-TextField label: use `assertVisible` with an explicit `text:` regex; expose the value via HTTP and fetch from `runScript`; or — if the value is genuinely dynamic (OTP, generated token, price shown in an image) — use `extractTextWithAI: "your natural-language query"` which puts the result in `${aiOutput}`.
- `tapOn: "Submit"` / `assertVisible: "Submit"` still work on Text widgets because the shorthand matches `accessibilityText`.

## Gotcha #2 — ListTile-family widgets merge children into one multi-line `accessibilityText`

Flutter automatically merges semantic children of these widgets into a single `accessibilityText` with newlines between them:

| Widget                                      | Example merged `accessibilityText`      |
|---------------------------------------------|-----------------------------------------|
| `ListTile`                                  | `"1\nItem 1\nRow index 0"`              |
| `SwitchListTile`                            | `"Notifications\nReceive pushes"`       |
| `CheckboxListTile`                          | `"I accept the terms"`                  |
| `RadioListTile`                             | (title + subtitle merged)               |
| `Tab(text: '…')` inside a `TabBar`          | `"Alpha\nTab 1 of 3"`                   |
| `Slider` with a nearby label `Text`         | `"Age: 30"` (Slider absorbs the label)  |
| `DropdownButtonFormField` w/ selected value | `"Country\nUSA"`                        |

Because Maestro's `text:` is **full-match regex**, `"Notifications"` does NOT match `"Notifications\nReceive pushes"`. Three ways out:

1. **Select by `id:`** — wrap the whole widget in `Semantics(identifier: 'my_id')` and use `id: "my_id"`. Recommended.
2. **DOTALL regex**: `text: "(?s).*Notifications.*"`. The `(?s)` inline flag makes `.` match newlines.
3. **Restructure** — replace `ListTile` with a `Row` so each `Text` remains a distinct node.

## Gotcha #3 — `Semantics(identifier:)` inside a ListTile slot gets absorbed

```dart
// What you write:
ListTile(
  title: const Text('Volume'),
  subtitle: Slider(...),
  trailing: Semantics(                       // <-- this Semantics
    identifier: 'volume_value',              // <-- this id
    child: Text('$percent%'),
  ),
)
```

```
// What ends up in the hierarchy:
{
  "accessibilityText": "Volume\n50%",        // subtitle + trailing merged
  "resource-id": "volume_slider",             // the slider's id survives
  // volume_value identifier is GONE — absorbed into the parent
}
```

**Fixes:**
- Move the `Semantics(identifier:)` **outside** the tile (wrap the whole tile).
- Accept the merge and assert by text: `assertVisible: "(?s).*Volume.*50%.*"`.
- Use a `Row` instead of `ListTile` so the trailing `Text` stays as its own node.

## Gotcha #4 — `Semantics` around an `IconButton` / `TextButton` / `Checkbox` / `Switch` loses its identifier

These widgets have their own built-in interactive semantics node (the label comes from the `tooltip:` for buttons, or from state for checkboxes). When you wrap one with `Semantics(identifier: 'foo', child: ...)`, Flutter merges the two nodes — and the inner interactive node wins. Your outer `identifier` silently vanishes.

Symptom: in `maestro hierarchy` you see a node with `accessibilityText: "Delete"` (from the tooltip) but **no `resource-id`** where you expected one.

Fix: add `container: true` to force a separate semantics node:

```dart
// WRONG — identifier absorbed by IconButton
Semantics(
  identifier: 'restore_btn',
  child: IconButton(tooltip: 'Restore', ...),
)

// RIGHT — container: true keeps them distinct
Semantics(
  identifier: 'restore_btn',
  container: true,
  child: IconButton(tooltip: 'Restore', ...),
)
```

Now the hierarchy has a node with `resource-id: "restore_btn"` wrapping the IconButton's node, and `id: "restore_btn"` works in Maestro.

**Rule of thumb**: if the widget you wrap already has its own interactive semantics (button, input, tappable), add `container: true`. Plain widgets like `Text`, `Card`, `Container`, `Row`, `Column` don't need it.

### The nastier variant — the `resource-id` appears but the tap silently misses

Absorption isn't always all-or-nothing. Sometimes the `resource-id` *does* surface in the hierarchy (so `assertVisible: id:` and `extendedWaitUntil: visible: id:` pass) — but the merged node's bounds are wrong, so `tapOn: id:` reports **COMPLETED while the tap lands on dead space** and nothing happens. Seen in practice with `Semantics(identifier:)` wrapping a `TextButton` inside `AlertDialog.actions` (no `container: true`).

Symptom: `tapOn: id: "foo"` → COMPLETED, but the dialog/screen doesn't change; the next `extendedWaitUntil` times out.

Fix (test-side, when you can't patch the app): tap the visible label instead — `tapOn:\n    text: "OK"`. Fix (app-side): add `container: true`. Don't trust "the id is in the hierarchy" to mean "the id is tappable".

> Note: `FilledButton` / `ElevatedButton` / `TextButton` that use a `Text` child (no tooltip) typically survive without `container: true` because the Text contributes the accessibilityText cleanly. But when in doubt, add it — the cost is zero.

## Gotcha #5 — `hideKeyboard` fails on Flutter iOS

```
Couldn't hide the keyboard. This can happen if the app uses a
custom input or doesn't expose a standard dismiss action.
```

Flutter iOS uses its own keyboard rendering and doesn't expose the standard iOS keyboard dismiss API to UI testing. **Do not use `- hideKeyboard` in Flutter iOS flows.** Instead:

1. **`- pressKey: "Enter"`** — the Flutter iOS keyboard's return key defaults to dismiss for single-line `TextField`s. ✅ reliable, use this first.
2. Tap a non-focusable area (e.g., the AppBar title) — inconsistent; only works if your app has a `GestureDetector(onTap: unfocus)` wrapping the page.
3. `- swipe:\n    start: "50%,50%"\n    end: "50%,95%"` — physically swipes the keyboard away. Works but fragile.

`hideKeyboard` is fine on Android and on native iOS apps. The problem is **Flutter iOS only**.

## Gotcha #6 — `- back` is unreliable on Flutter iOS

Maestro's `- back` command simulates the device-level back gesture. On Android that's the hardware back button and always works. On iOS there's no hardware back — the command tries an edge-swipe. For many Flutter screens (especially with `go_router` or custom AppBars) it silently no-ops.

**Reliable workaround on Flutter iOS**: tap the AppBar's back chevron by its accessibility label:

```yaml
# INSTEAD OF:
- back        # ❌ often no-op on Flutter iOS

# USE:
- tapOn: "Back"   # ✅ taps the AppBar chevron (accessibilityText: "Back")
```

When the chevron is hidden (e.g. `automaticallyImplyLeading: false` or `leading: SizedBox.shrink()`), add your own explicit back button and tap it by its `Semantics(identifier:)` (remember `container: true` if you use an IconButton).

## Gotcha #7 — Snackbars block taps on widgets near the bottom of the screen

A `SnackBar` in Flutter sits at the bottom of the Scaffold on top of the content. While it's visible (default ~4 seconds), taps that overlap its area may not reach the widget underneath — the tap "completes" per Maestro's log but the underlying widget (commonly a checkbox or bottom-anchored button) doesn't receive the event.

Symptom: tap reports COMPLETED, the widget's state doesn't change (checkbox stays unchecked, button click doesn't fire).

Fix: wait for the snackbar to dismiss before the next tap:

```yaml
- tapOn:
    id: "submit_without_acceptance"
- assertVisible: "(?s).*Please accept the terms.*"
- extendedWaitUntil:
    notVisible: "(?s).*Please accept the terms.*"
    timeout: 8000
- tapOn:
    id: "terms_checkbox"           # now it actually registers
- tapOn:
    id: "submit"
```

## Gotcha #8 — `scrollUntilVisible` can overshoot on lazy `ListView.builder`

Flutter's `ListView.builder` / `ListView.separated` **lazy-renders** items. Off-screen items aren't in the widget tree at all. `scrollUntilVisible` has to scroll, re-render, check visibility, repeat.

Default `speed` (~100) is fast; on fast scrolls, target items flick past without ever hitting the default `visibilityPercentage: 100`. The fix:

```yaml
- scrollUntilVisible:
    element:
      id: "list_item_30"
    direction: DOWN
    timeout: 15000          # raise from default 10000
    speed: 40               # slower scroll → each frame has time to settle
    visibilityPercentage: 50  # found when 50% visible
```

Rule of thumb for Flutter: `speed: 40` and `visibilityPercentage: 50` on any list with more than ~20 items.

## Gotcha #9 — `scrollUntilVisible` no-ops on items inside Flutter's cacheExtent

Flutter's `ListView` renders a few items **just outside** the visible viewport (the "cacheExtent"). Those items appear in the accessibility tree with tiny bounds like `[16,851][377,852]` — 1 pixel tall at the screen edge. Maestro's default `scrollUntilVisible` considers them "visible enough" and returns COMPLETED without actually scrolling. The subsequent `tapOn` fires at those off-screen coordinates and silently misses.

Symptom: both commands report COMPLETED, the screen doesn't change, the next `assertVisible` fails.

Fix: add `centerElement: true` to force Maestro to scroll until the target is centered:

```yaml
- scrollUntilVisible:
    element:
      id: "bottom_item"
    direction: DOWN
    speed: 40
    centerElement: true       # ← force a real scroll even for cacheExtent items
- tapOn:
    id: "bottom_item"         # now genuinely visible and tappable
```

## Adding stable identifiers to Flutter widgets

```dart
// Plain child (Text, Card, Container) — no container: true needed
Semantics(
  identifier: 'welcome_banner',
  child: const Text('Welcome'),
)

// Interactive child (IconButton, Checkbox, Switch, Radio, TextButton) — container: true REQUIRED
Semantics(
  identifier: 'delete_btn',
  container: true,
  child: IconButton(
    icon: const Icon(Icons.delete),
    tooltip: 'Delete',
    onPressed: _delete,
  ),
)

// Lists — index the identifier so individual rows are addressable
ListView.builder(
  itemBuilder: (_, i) => Semantics(
    identifier: 'note_tile_$i',
    child: ListTile(...),                  // Semantics OUTSIDE ListTile, not inside
  ),
)

// Text-input fields
Semantics(
  identifier: 'email_field',
  child: TextFormField(...),
)
```

## Do NOT rely on Flutter `Key`

`Key(ValueKey('foo'))` and `GlobalKey` do **not** surface in Maestro's hierarchy. They're Flutter framework constructs for widget identity, not accessibility. Only `Semantics` is visible to the accessibility tree — and therefore to Maestro.

## Flutter iOS simulator launch time

The first Maestro run after a simulator reboot can take 5-10 minutes because Maestro reinstalls its iOS XCUITest driver. Subsequent runs are fast (5-15s per flow). If you see your test frozen at "Starting test-without-building…" with high CPU use, that's the driver install — wait it out once.

To skip the reinstall on later runs: `maestro test --no-reinstall-driver ...`.

## Debug checklist — Flutter-specific

1. `maestro hierarchy` — dump the screen. Is the element there? What are its `accessibilityText`, `resource-id`, `text` values?
2. Is the target inside a `ListTile` family widget, `Tab`, `DropdownButtonFormField`, or `Slider`? If yes, its text is merged — use `id:` or DOTALL regex (Gotcha #2).
3. Is your `Semantics(identifier:)` wrapping an interactive widget (IconButton, Checkbox, Switch, Radio, TextButton)? If yes and there's no `resource-id` in the hierarchy, add `container: true` (Gotcha #4).
4. Is it a keyboard dismissal step? Use `pressKey: "Enter"`, never `hideKeyboard` (Gotcha #5).
5. Is it `copyTextFrom` on a Text widget? Rewrite as `assertVisible` with a `text:` regex (Gotcha #1).
6. Is it a back navigation? Use `tapOn: "Back"`, not `- back` (Gotcha #6).
7. Did a snackbar just appear, and you're now trying to tap something near the bottom? Wait for the snackbar to dismiss (Gotcha #7).
8. Is the target below the fold in a long list? `scrollUntilVisible` with `speed: 40, visibilityPercentage: 50, centerElement: true` (Gotchas #8 & #9).
9. Still no clue? `maestro test --debug-output ./debug flow.yaml` — saves screenshots + per-command logs.
