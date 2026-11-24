---
name: maestro
description: Write, run, and debug Maestro mobile UI tests (YAML flows) for iOS simulators, Android emulators, and especially Flutter apps. Use whenever the user mentions Maestro, UI automation, end-to-end mobile tests, device flows, `maestro test`, `.maestro/flows`, hierarchy dumps, or wants to script taps / inputs / assertions / swipes / scrolls against a running app. Covers flow syntax, selectors (with the full-match regex rule that contradicts the docs), Flutter's Semantics mapping, workspace config.yaml (including `flows:` globs, `executionOrder`, platform tuning, Maestro Cloud settings), env vars (CLI `-e`, frontmatter, built-ins like `MAESTRO_SHARD_ID`, shell `MAESTRO_*` capture), JavaScript scripting (evalScript inline vs block, runScript, http, output), AI commands (assertWithAI, extractTextWithAI), sharding, and the hard-won Flutter gotchas (ListTile merging, IconButton needing `container: true`, `hideKeyboard` failing on Flutter iOS, `- back` no-op on go_router, snackbars blocking taps, `scrollUntilVisible` no-op on cacheExtent items).
---

# Maestro

> **Boilerplate note:** This skill is kept as a reference pattern. Some examples reference push notifications / FCM-driven navigation — that live FCM / Firebase code is **NOT** present in this boilerplate (it was removed), so those flows are illustrative until you add the feature back. The generic flow syntax, selectors, and Flutter gotchas below apply as-is.

Maestro drives iOS simulators, Android emulators, and physical devices via declarative YAML flows. One flow = one file = one sequence of commands, executed top-to-bottom, stopping on first failure.

## References — load the one that matches your current problem

- `references/commands.md` — every command with full parameter grammar, defaults, examples. Load when you need exact syntax for a specific command.
- `references/selectors.md` — full selector grammar: text, id, index, relational (`below`, `childOf`, `containsChild`), state, regex rules, escaping. Load when the selector won't match and the SKILL.md section below isn't enough.
- `references/flutter.md` — Flutter-specific traps with app-side fixes. **Load first when testing any Flutter app** — the 9 gotchas here account for most wasted debugging time.
- `references/javascript.md` — `evalScript`, `runScript`, `assertTrue`, `${...}` substitution, `output.*` persistence quirks, `http` client. Load when you're mixing logic into YAML.
- `references/recipes.md` — 20+ copy-paste flow patterns: login, search, list scroll, multi-step wizard with branching, back navigation, pull-to-refresh, dialog, snackbar, permissions, hooks, tag filtering, data-driven env. Load when the user asks for a flow shape you haven't written before.
- `references/debugging.md` — a 10-step diagnostic checklist for when a flow misbehaves. Load when a specific flow is failing and you've already dumped the hierarchy.

## The 6-step workflow

1. **Know the appId.** iOS bundle id (`com.example.app`) or Android package name. Set at the top of each flow or in `.maestro/config.yaml`.
2. **Boot a device.** `xcrun simctl list devices booted` (iOS) / `adb devices` (Android). `xcrun simctl boot <UDID>` or start an emulator if none running. **If more than one device/simulator is booted, `maestro test` and `maestro hierarchy` print "Choose a device" and hang waiting on stdin** — always pass `--device <udid>` explicitly when multiple devices exist (e.g. `maestro --device <udid> test ...`).
3. **Dump the hierarchy: `maestro hierarchy`.** This is your single most important tool — it prints the accessibility tree of the current screen, showing every attribute Maestro can match against. Always check the hierarchy before guessing a selector. Guessing wastes hours.
4. **Write the flow** using selectors you *confirmed* exist in the hierarchy. Prefer `id:` over `text:` when the app exposes identifiers — it survives copy changes, theming, and localization.
5. **Run it**: `maestro test path/to/flow.yaml`. Each command prints as it runs; a failure halts the flow and dumps debug artifacts to `~/.maestro/tests/<timestamp>/`.
6. **If a step fails**, read the exact error line, then dump the hierarchy at the failing point (insert a temporary `- assertVisible: "zzz"` to stop there), and compare what Maestro sees vs what you expected.

## Flow file anatomy

```yaml
appId: dev.example.app           # required — unless set in .maestro/config.yaml
tags: [smoke, login]             # optional — filter with --include-tags / --exclude-tags
env:                             # optional — default values for ${VAR} substitution
  USERNAME: user@test.com
name: Login flow                 # optional display name
onFlowStart:                     # optional — commands run before the main flow
  - launchApp:
      clearState: true
onFlowComplete:                  # optional — commands run after (always, even on failure)
  - takeScreenshot: "final"
---
- launchApp                      # commands start after the --- separator
- tapOn: "Sign In"
- inputText: "${USERNAME}"
- assertVisible: "Welcome"
```

The `---` separator between frontmatter and commands is **required**, even if the frontmatter is just `appId:`.

A workspace-level `config.yaml` (at repo root or in `.maestro/`) provides defaults and workspace-wide controls. The full grammar:

```yaml
# .maestro/config.yaml
appId: dev.example.app           # default appId for every flow in the workspace
flows:                            # glob patterns — which flows are part of this workspace
  - 'smoke/*'
  - 'e2e/**'                      # ** = recursive
testOutputDir: ~/.maestro/tests   # where debug artifacts go

# Filtering — same semantics as --include-tags / --exclude-tags
includeTags: [smoke, login]
excludeTags: [slow, broken]

# Execution order
executionOrder:
  continueOnFailure: true         # default true — set false to stop the whole suite on first flow failure
  flowsOrder:                     # optional — explicit order; unlisted flows run after in discovery order
    - 01_smoke
    - 02_checkout

# Platform tuning (most options are Maestro Cloud only)
platform:
  ios:
    disableAnimations: true
    snapshotKeyHonorModalViews: false
  android:
    disableAnimations: true

# Maestro Cloud
baselineBranch: main
notifications:
  email:
    enabled: true
    recipients: [team@example.com]
  slack:
    endpoint: "https://hooks.slack.com/services/…"
---
name: My App Tests
```

You can keep multiple configs (e.g. `.maestro/ci-config.yaml`) and select one with `maestro test --config .maestro/ci-config.yaml tests/`.

## The ten most-used commands

Reach for these first. See `references/commands.md` for every parameter.

| Command                | Purpose                              | Minimal form                                             |
|------------------------|--------------------------------------|----------------------------------------------------------|
| `launchApp`            | Start / focus the app                | `- launchApp` or `- launchApp:\n    clearState: true`    |
| `tapOn`                | Tap an element                       | `- tapOn: "Submit"` or `- tapOn:\n    id: "submit_btn"`  |
| `inputText`            | Type into focused field              | `- inputText: "hello"`                                   |
| `pressKey`             | Dismiss keyboard on Flutter iOS      | `- pressKey: "Enter"`                                    |
| `hideKeyboard`         | Dismiss keyboard (native iOS / Android) | `- hideKeyboard`                                      |
| `scroll`               | Scroll current scrollable one page   | `- scroll`                                               |
| `scrollUntilVisible`   | Scroll until element visible         | `- scrollUntilVisible:\n    element:\n      id: "row_5"` |
| `swipe`                | Directional swipe                    | `- swipe:\n    direction: LEFT`                          |
| `assertVisible`        | Assert element present               | `- assertVisible: "Welcome"`                             |
| `extendedWaitUntil`    | Wait up to N ms for a condition      | `- extendedWaitUntil:\n    visible: "X"\n    timeout: 10000` |

## Selectors — the essentials

Full reference: `references/selectors.md`.

**Shorthand** (bare string) = regex against multiple attributes (text, accessibilityText, id, hint):
```yaml
- tapOn: "Sign In"
```

**Full form** (map) = explicit fields, ANDed together:
```yaml
- tapOn:
    id: "login_submit_button"    # most stable — prefer this when available
    text: "^Sign In$"            # regex — anchor with ^...$ for exact
    index: 0                     # 0-based pick when multiple match
    enabled: true                # state filter
    containsChild:               # relational — parent of a matching child
      text: "Delete"
    below:                       # positional — nearest below an anchor
      text: "Email"
    point: "50%,50%"             # last resort: coordinates
    optional: true               # skip silently if not found
```

### The one rule that will bite you until you memorize it

**`text:` and the shorthand string form are BOTH full-match regex**, not substring search. `"Sign"` does NOT match `"Sign In"` — the entire attribute must match the pattern. Also, regex `.` does not match newlines by default.

So the three most common wrong assumptions are:
- "Substring search" — no, use `.*needle.*` to match a fragment.
- "Literal string" — no, escape regex metacharacters: `?` → `\\?`, `.` → `\\.`, `$` → `\\$`, `(` → `\\(`, etc. YAML needs double-backslash for a single `\`.
- "Works on multi-line text" — no, prepend `(?s)` for DOTALL: `"(?s).*Grocery list.*"`.

When in doubt, prefer `id:` — it's a literal match (not regex) and sidesteps all of this.

## Platform identifier mapping

| Platform        | In your app                              | Shows up in hierarchy as  | Select via            |
|-----------------|------------------------------------------|---------------------------|-----------------------|
| iOS (UIKit)     | `accessibilityIdentifier`                | `resource-id`             | `id:`                 |
| iOS (UIKit)     | `accessibilityLabel`                     | `accessibilityText`       | `text:` or shorthand  |
| Android         | `android:id` or Compose `testTag`        | `resource-id`             | `id:`                 |
| Android         | `contentDescription`                     | `accessibilityText`       | `text:` or shorthand  |
| Flutter         | `Semantics(identifier: 'foo')`           | `resource-id: "foo"`      | `id: "foo"`           |
| Flutter         | `Semantics(label: 'foo')` OR `Text('X')` | `accessibilityText: "X"`  | `text:` or shorthand  |

On Flutter, the `text` attribute is **always empty for app content** (`Text('Welcome')` exposes its content in `accessibilityText`, not `text`). Only iOS SystemUI populates `text`. This has real consequences — read `references/flutter.md` before writing any Flutter flow.

## Flutter gotchas — the short list

These are the ones that actually bite in practice. Each has a matching entry in `references/flutter.md` with code fixes.

### Selector absorption (your `id:` disappears from the hierarchy)

1. **`Semantics(identifier:)` inside a `ListTile` subtitle/trailing/leading is absorbed.** ListTile merges all children into one node — the outer identifier wins (if present) but nested identifiers are lost. Move the `Semantics` outside the tile, or don't use ListTile.
2. **`Semantics(identifier:)` wrapping an `IconButton` / `Checkbox` / `Switch` / `Radio` / `TextButton` / anything with a tooltip also gets absorbed.** Symptom: hierarchy shows the tooltip in `accessibilityText` but no `resource-id`. Fix: add `container: true` to the Semantics wrapper — forces a separate node. Plain `Text` / `Container` / `Card` don't need it.
3. **`ListTile`-family widgets merge children into one multi-line `accessibilityText`** (e.g. `"1\nItem 1\nRow index 0"`). Full-match regex `"Item 1"` won't match — use `"(?s).*Item 1.*"` or select by `id:`.

### Input

4. **`hideKeyboard` fails on Flutter iOS** with *"Couldn't hide the keyboard…"*. Use `- pressKey: "Enter"` instead — Flutter's iOS keyboard treats return as dismiss for single-line `TextField`s.
5. **`copyTextFrom` returns `undefined` for Flutter `Text` widgets** because it reads the `text` attribute which is empty for them. (A `TextField`'s `text` attribute IS populated with its live input value — that works.) For labels, rewrite the check as `assertVisible:` with an explicit `text:` regex.

### Navigation

6. **`- back` is unreliable on Flutter iOS** (especially with `go_router`) — it often silently no-ops. Tap the AppBar chevron instead: `- tapOn: "Back"` (the Material back icon exposes `accessibilityText: "Back"`). If you've hidden the leading chevron, add your own Semantics-identified back button.

### Timing & scrolling

7. **Snackbars block taps on widgets near the bottom** for their ~4-second lifetime. If your flow fires a snackbar then immediately tries to tap a checkbox / bottom button, the tap "completes" per Maestro's log but the widget doesn't receive it. Wait for the snackbar to dismiss with `- extendedWaitUntil:\n    notVisible: "(?s).*<snackbar text>.*"\n    timeout: 8000`.
8. **`scrollUntilVisible` can no-op on items in Flutter's `cacheExtent`** — off-screen items show up in the accessibility tree with 1-pixel-tall bounds at the screen edge, and the default visibility check considers them "found". The subsequent `tapOn` fires at those off-screen coordinates and misses. Fix: add `centerElement: true` to force a real scroll.
9. **`ListView.builder` + `scrollUntilVisible` default speed can overshoot targets** on long lists. Use `speed: 40, visibilityPercentage: 50` (40 slow enough to not flick past items, 50 accepts half-visible as found).

### Regex metacharacters in UI copy

10. Strings like `"Are you sure?"`, `"$9.99"`, `"[beta]"` contain regex metacharacters. `"?"` makes the preceding `s` optional — so `"Are you sure?"` matches `"Are you sur"` or `"Are you sure"`, not the literal question mark. Escape with `\\`: `"Are you sure\\?"`. Or sidestep with `id:`.

## JavaScript in flows

Full reference: `references/javascript.md`. The two non-obvious rules:

1. **`evalScript: |` multi-line block does NOT persist `output.*`.** Only the inline form works:
   ```yaml
   - evalScript: ${output.x = 5}          # works — output.x is available later
   - evalScript: |                        # does NOT persist output.x
       output.x = 5;
   - runScript: scripts/setup.js          # use this for multi-line logic — output DOES persist
   ```
2. **`${output.x}` substitution in `times:` is unreliable** — `repeat:` interprets the unresolved value as "repeat indefinitely". Use frontmatter `env:` instead:
   ```yaml
   env:
     N: 5
   ---
   - repeat:
       times: ${N}                        # works
       commands: [...]
   ```

## Running flows

```bash
maestro test flow.yaml                        # single flow
maestro test .maestro/flows/                  # all flows in a folder
maestro test -e USERNAME=alice flow.yaml      # env var — overrides frontmatter defaults
maestro test --include-tags smoke .maestro/flows/
maestro test --debug-output ./debug flow.yaml # save screenshots + per-command logs
maestro test --no-reinstall-driver flow.yaml  # skip xctest driver reinstall (faster)
maestro test --config .maestro/ci.yaml tests/ # pick a specific workspace config
maestro test --shards 3 tests/                # split the suite across 3 parallel shards
maestro test --format HTML --output report.html tests/
maestro hierarchy                             # print current screen tree — #1 debug tool
maestro start-device                          # boot a simulator/emulator
maestro check-syntax flow.yaml                # lint only, no device needed
```

Maestro auto-injects `MAESTRO_SHARD_ID`, `MAESTRO_SHARD_INDEX`, `MAESTRO_DEVICE_UDID`, and `MAESTRO_FILENAME` as env vars for each run — useful for disambiguating test output in parallel shards. Any shell env var prefixed with `MAESTRO_` is auto-captured into the flow (handy for CI secrets).

## Golden rules

- **Dump the hierarchy first** when you don't know the exact selectors. Never guess.
- **Prefer `id:` over `text:`** whenever the app exposes identifiers. Survives copy / localization / theming.
- **Treat `text:` as full-match regex** — `.*needle.*` for substring, `(?s).*needle.*` for multi-line.
- **Use `extendedWaitUntil` for async transitions**, not bare `assertVisible`.
- **Don't race transient states** (spinners, toasts) — assert the final state instead.
- **Add `clearState: true`** to `launchApp` when you need a known starting point.
- **For Flutter iOS**: `pressKey: "Enter"` over `hideKeyboard`, `tapOn: "Back"` over `- back`, avoid `copyTextFrom`, always add `container: true` when wrapping interactive widgets in `Semantics`.
- **For below-the-fold targets**: wrap with `scrollUntilVisible` + `centerElement: true`.
- **Don't run `maestro hierarchy` or other Maestro commands during a running test suite** — they fight over the XCUITest driver on port 7001 and everything after fails. If it happens: `kill $(ps aux | grep -v grep | grep -E "maestro-driver|java.*AppKt" | awk '{print $2}')`, then rerun.

## Quick skeleton

Copy and adapt:

```yaml
appId: com.example.app
---
- launchApp:
    clearState: true
# Dismiss any consent/cookie popup that may or may not show up
- runFlow:
    when:
      visible: "Accept cookies"
    commands:
      - tapOn: "Accept"
- tapOn:
    id: "login_tab"
- tapOn:
    id: "email_field"
- inputText: "user@test.com"
- pressKey: "Enter"                 # dismiss keyboard on Flutter iOS
- tapOn:
    id: "password_field"
- inputText: "secret"
- pressKey: "Enter"
- tapOn:
    id: "submit_btn"
- extendedWaitUntil:
    visible:
      id: "welcome_banner"
    timeout: 10000
- assertVisible: "Welcome"
```

For longer patterns (forms, lists, multi-step wizards, dialogs, gestures, deep links, permissions, hooks, tag filtering) see `references/recipes.md`.
