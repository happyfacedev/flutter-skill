# Maestro debugging reference

Load this when a flow is misbehaving and you need a systematic way to find the cause. Work through the checklist top-to-bottom — early steps rule out the cheap mistakes so you don't waste time on complex theories.

## Step 1: Dump the live hierarchy

```bash
maestro hierarchy
```

This prints the accessibility tree of whatever is on screen right now. Use it to verify:
- **Is the element actually there?** If the hierarchy doesn't contain your target at all, your selector can't possibly match.
- **What are its exact attributes?** Especially `accessibilityText`, `text`, `resource-id`, `hintText`. On Flutter, `text` is almost always empty — look at `accessibilityText` instead.
- **Is the text merged across lines?** Look for `\n` in `accessibilityText`. If you see `"Volume\n50%"`, your `text: "Volume"` full-match regex won't work — use `"(?s).*Volume.*"` or an `id:`.

Cheap trick: write a throwaway flow that navigates to the problem screen, add `- waitForAnimationToEnd` at the end, run it, and then run `maestro hierarchy` while the app is on that screen.

## Step 2: Check the selector semantics

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| "Element not found: Text matching regex: Foo" | `text:` is full-match regex, element's text is longer | `text: ".*Foo.*"` or select by `id:` |
| "Element not found" but you can see it | Text spans multiple lines (typical of Flutter ListTile) | `text: "(?s).*Foo.*"` (DOTALL) |
| Tapped wrong element | Multiple matches, you got index 0 | Add `index:`, or narrow with `containsChild:` / relational |
| Shorthand `tapOn: "X"` works but `text: "X"` doesn't | Shorthand searches more attrs than `text:` | Use shorthand, or switch to `id:` |
| `copyTextFrom: id: "..."` returns undefined | Flutter: `text` attr is empty | Don't use copyTextFrom on Flutter — `assertVisible` with explicit `text:` regex |

## Step 3: Check timing

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Assertion fails on something you know appears | UI not ready yet | `- extendedWaitUntil:\n    visible: ...\n    timeout: 10000` |
| Transient state (spinner for 500ms) can't be caught | Race — spinner gone by the time assertion runs | Don't try — assert the final state after the transition |
| Tap fires but nothing happens | Animation still running | `- waitForAnimationToEnd` before the tap |
| First-run of a flow takes forever | Maestro reinstalling XCUITest driver | Wait it out once; subsequent runs are fast. Add `--no-reinstall-driver` to skip |

## Step 4: Check visibility

If your target exists in the hierarchy (step 1) but `assertVisible` fails — or if your `tapOn` "completes" per Maestro's log but the widget doesn't react — it's probably covered by something:

- **Below the fold?** Wrap with `- scrollUntilVisible: element: ...`. On Flutter, add `centerElement: true` to force a real scroll when the item is already in the cacheExtent (its bounds would be a 1-pixel strip at the screen edge).
- **Behind a keyboard?** Dismiss first — `- pressKey: "Enter"` on Flutter iOS (`hideKeyboard` fails there), `- hideKeyboard` elsewhere.
- **Behind a snackbar?** Flutter snackbars overlay the bottom of the Scaffold for ~4s and block taps to widgets beneath them. Wait it out: `- extendedWaitUntil:\n    notVisible: "(?s).*<snackbar text>.*"\n    timeout: 8000`.
- **Behind a dialog / bottom sheet?** Dismiss the overlay first.
- **Element in a horizontally scrollable list?** `scrollUntilVisible` with `direction: RIGHT`.

## Step 5: Check state

State leaking from previous runs is a common gremlin. Symptoms:
- Login succeeds without typing because app remembered session.
- Onboarding screen skipped because "already seen" flag was persisted.
- Counter starts at non-zero because HydratedBloc restored.

Fixes:
```yaml
- launchApp:
    clearState: true       # wipe local storage, shared prefs, NSUserDefaults
    clearKeychain: true    # iOS: also wipe keychain (auth tokens)
```

Or as standalone commands:
```yaml
- clearState
- clearKeychain
- launchApp
```

## Step 5.5: App-level traps that manifest as Maestro failures

Sometimes the test is correct and the app is buggy. Most common culprits on Flutter:

| Symptom                                                  | Likely app bug                                                   |
|----------------------------------------------------------|------------------------------------------------------------------|
| `tapOn` a button "completes" but the UI doesn't change   | Button is disabled (`onPressed: null`), or wrapped in a widget that swallows taps (e.g. `AbsorbPointer`) |
| `back` or `context.pop()` does nothing                   | `PopScope(canPop: false, ...)` is blocking; check the screen's stateful widget |
| Save button pressed but screen doesn't navigate          | The navigation runs `context.pop()` immediately after `setState`, but `PopScope.canPop` is read before the rebuild. Fix in the app: schedule the pop with `WidgetsBinding.instance.addPostFrameCallback` |
| Dialog appears briefly then re-appears on its own        | `PopScope` callback loop — the discard-confirm path calls `context.pop()` while the dirty flag is still true. Reset the flag before the second pop. |
| Tapping AppBar icon while TextField focused does nothing | Some Flutter `PopScope` bugs — unfocus the TextField first by tapping a non-input area (AppBar title works) or `pressKey: "Enter"`. |

If you hit one of these, it's a bug in the **app**, not your flow. Fix the app — don't work around it with brittle test tricks.

## Step 6: Check JavaScript assumptions

| Symptom | Cause | Fix |
|---------|-------|-----|
| `${output.x}` resolves to `undefined` after `evalScript: \|` block | **Block form of evalScript does NOT persist `output.*`** | Use inline `evalScript: ${output.x = ...}` or `runScript: file.js` |
| `times: ${output.n}` causes infinite repeat | Substitution from evalScript output may not work in `times:` parameter | Pass via `env:` frontmatter: `env: N: 5` then `times: ${N}` |
| `assertTrue: ${output.a === output.b}` fails unexpectedly | One of them is a string, the other number | Use `==` (loose), or `parseInt()`, or log with `assertVisible: "a=[${output.a}]_b=[${output.b}]"` |
| `maestroCopiedText` is undefined | `copyTextFrom` selector matched but element's `text` field is empty (Flutter quirk) | Don't copyTextFrom from Flutter content; restructure assertion |

## Step 7: Write a tighter reproduction

If you still can't figure it out, reduce. Copy the flow to `/tmp/repro.yaml`, delete everything except the minimal steps that reproduce the failure, then:

1. Add `- waitForAnimationToEnd` before the failing step.
2. Add `- takeScreenshot: "before_fail"` before and `- takeScreenshot: "after_fail"` after — check the resulting PNGs in `/Users/$USER/.maestro/tests/<timestamp>/`.
3. Run with `--debug-output ./debug` to save per-command logs + screenshots to a predictable path.
4. `maestro hierarchy` immediately after the setup (before the failing step) to compare what Maestro sees vs what you expect.

## Step 7.5: XCUITest driver got stuck

If you see any of these on iOS:

- `Unable to set permissions for app XXX: Failed to connect to /127.0.0.1:7001`
- `App crashed or stopped while executing flow`
- First flow passes, then the second onward fails with connection errors
- Tests hang forever at "Starting test-without-building..."

The XCUITest driver (Maestro's iOS bridge) got into a bad state, usually after:
- A previous `maestro test` was killed (Ctrl-C or external `kill`).
- The simulator was rebooted during a test.
- A test caused the app to crash in a way that broke the driver connection.

Fix:

```bash
# Kill everything Maestro-related
kill $(ps aux | grep -v grep | grep -E "maestro-driver|java.*AppKt" | awk '{print $2}') 2>/dev/null

# Optionally stop the app if it's still in the simulator
xcrun simctl terminate booted <your.app.bundle.id> 2>/dev/null

# Wait a couple of seconds for the simulator to settle
sleep 3

# Re-run — Maestro will reinstall the driver automatically
maestro test flow.yaml
```

If that doesn't work, rebooting the simulator via `xcrun simctl shutdown booted && xcrun simctl boot <UDID>` usually does.

## Step 8: Check for environment peculiarities

- **iOS simulator not booted?** `xcrun simctl list devices booted` — boot one with `xcrun simctl boot <UDID>`.
- **Multiple simulators booted?** Maestro picks one non-deterministically. Target a specific one with `--udid`.
- **Android emulator not detected?** `adb devices` should list it. Restart adb: `adb kill-server && adb start-server`.
- **Test on Apple Silicon via x86 simulator?** Known to be slow and flaky — use an arm64 simulator.

## Step 9: Verify appId

Forgot to update `appId:` after renaming the app? The launch command succeeds (finds nothing to install) but every `assertVisible` fails because your flow is looking at the wrong app.

```bash
# iOS — list installed app bundle ids on the booted simulator
xcrun simctl listapps booted | grep -i yourApp

# Android
adb shell cmd package list packages | grep yourApp
```

## Step 10: When all else fails

1. `maestro --version` — check you're on a recent Maestro (major changes in 1.x → 2.x).
2. Search GitHub issues: https://github.com/mobile-dev-inc/Maestro/issues
3. `maestro bugreport` — generates a bundle Maestro's team can analyze.
4. Simplify by switching to a brand-new flow that mimics docs exactly — if that also fails, your environment is broken, not your flow.

## Useful output locations

- **Per-test debug**: `~/.maestro/tests/<date>_<time>/` — screenshots, command logs, AI report.
- **Explicit debug dir**: `--debug-output ./my_debug` — same contents, chosen path.
- **Test report**: `--format HTML --output report.html` — shareable HTML report.
- **Video**: `--format HTML-DETAILED` — includes video of the run.

## Debug-output file structure

```
~/.maestro/tests/2026-04-21_113506/
├── commands-(flow_name.yaml).json    # every command + evaluated form + duration
├── screenshot-<status>-<time>-*.png  # screenshots on each significant step
├── ai-(flow_name).json               # AI assertion context (if used)
└── ai-report-<flow_name>.html        # readable AI report
```

Read `commands-*.json` to see the actual parameters Maestro executed after substitution — helpful when template variables silently don't resolve.
