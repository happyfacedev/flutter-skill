# Maestro commands reference

Every command with YAML syntax, parameters, and defaults. Load this when you need exact syntax for a specific command, or when picking between similar options (e.g. `scroll` vs `scrollUntilVisible`).

## Table of contents

- [App lifecycle](#app-lifecycle) — launchApp, stopApp, killApp, clearState, clearKeychain
- [Taps and gestures](#taps-and-gestures) — tapOn, doubleTapOn, longPressOn, swipe, back, pressKey
- [Text input](#text-input) — inputText, inputRandomText, eraseText, hideKeyboard, pasteText, setClipboard, copyTextFrom
- [Scrolling](#scrolling) — scroll, scrollUntilVisible
- [Assertions](#assertions) — assertVisible, assertNotVisible, assertTrue, assertWithAI, assertNoDefectsWithAI, assertScreenshot, extractTextWithAI
- [Waiting](#waiting) — waitForAnimationToEnd, extendedWaitUntil
- [Flow control](#flow-control) — runFlow, runScript, evalScript, repeat, retry
- [Device configuration](#device-configuration) — setLocation, setOrientation, setPermissions, setAirplaneMode, toggleAirplaneMode, travel
- [Media and recording](#media-and-recording) — takeScreenshot, startRecording, stopRecording, addMedia
- [Deep links](#deep-links) — openLink

---

## App lifecycle

### launchApp

```yaml
- launchApp                             # simplest — foregrounds the app
- launchApp: "com.other.app"            # shorthand — launch a specific bundle/package id
- launchApp:
    appId: "com.other.app"              # override top-level appId
    clearState: true                    # default false — wipe local data (same as clearState command)
    clearKeychain: true                 # default false — iOS: wipe the entire Keychain
    stopApp: true                       # default true — false = bring backgrounded app to foreground without restart
    permissions:                        # default: all granted. Set to grant/deny/unset.
      all: allow                        # shortcut: allow / deny / unset everything
      camera: deny
      location: always                  # allow / deny / unset / always / whenInUse
      android.permission.ACCESS_FINE_LOCATION: deny    # Android: exact permission strings also accepted
    arguments:                          # pass typed launch arguments (iOS reads from NSProcessInfo, Android as intent extras)
      SOME_FLAG: "string value"
      isEnabled: true
      fooDouble: 3.24
      fooInt: 3
```

Note: the parameter is `arguments:` in current Maestro. Older tutorials sometimes show `launchArguments:` — prefer `arguments:`.

### stopApp

Gracefully stop without clearing state. The app can resume where it left off on next `launchApp`.

```yaml
- stopApp
- stopApp: "com.other.app"              # stop a different app than the default
```

### killApp

Force-terminate. Same as stopApp but more aggressive (SIGKILL on Android).

```yaml
- killApp
```

### clearState

Wipe app data (same as reinstall). Does NOT launch the app afterwards — follow with `launchApp`.

```yaml
- clearState
- clearState: "com.other.app"
```

### clearKeychain

iOS only. Wipe keychain entries for the app. Useful for clearing persisted auth tokens.

```yaml
- clearKeychain
```

---

## Taps and gestures

### tapOn

See `references/selectors.md` for the complete selector grammar. The `tapOn` map accepts every selector field plus tap-specific options.

```yaml
- tapOn: "Submit"                       # shorthand: text/accessibilityText/id regex
- tapOn:
    id: "submit_btn"                    # stable identifier (regex internally — treat as literal)
    text: "Submit"                      # combined with id — BOTH must match
    index: 1                            # 0-based; pick the 2nd match
    point: "50%,80%"                    # fallback: tap screen coordinates (pct or pixels)
    enabled: true                       # match only enabled elements
    checked: false
    selected: true
    focused: true
    containsChild:                      # match parent of a matching child
      text: "Delete"
    below:                              # relational — see selectors.md
      text: "Email"
    optional: true                      # don't fail if not found
    retryTapIfNoChange: true            # default FALSE — set true to re-tap if UI didn't change
    waitToSettleTimeoutMs: 2000         # wait for animations before/after tap
    repeat: 3                           # tap N times (default 1)
    delay: 100                          # ms between repeat taps (default 100)
```

`tapOn` does not have a `longPress:` flag — use the dedicated `longPressOn` command instead. If you need to tap a specific point within a matched element (e.g. a hyperlink inside a paragraph), combine a selector with `point:` — the coordinates are relative to the matched element's bounds.

### doubleTapOn

Same selector grammar as `tapOn`.

```yaml
- doubleTapOn: "Zoom target"
- doubleTapOn:
    id: "image_tile"
```

### longPressOn

Same selector grammar as `tapOn`. Duration is fixed (~1 second); Maestro doesn't expose a duration knob.

```yaml
- longPressOn: "Message bubble"
- longPressOn:
    id: "context_menu_trigger"
```

### swipe

Three officially-documented forms: directional, coordinate-based, and `from:` element + direction.

```yaml
# 1. Directional — Maestro picks start/end automatically
- swipe:
    direction: LEFT                     # LEFT | RIGHT | UP | DOWN
    duration: 400                       # ms (default 400); shorter = flick, longer = drag

# 2. From a specific element
- swipe:
    from:
      id: "card_3"
    direction: UP

# 3. Coordinate-based — exact control
- swipe:
    start: "50%,80%"                    # percentage or absolute pixel
    end: "50%,20%"
    duration: 600

# Optional settling wait after the swipe
- swipe:
    direction: UP
    waitToSettleTimeoutMs: 500
```

A `from:` + `to:` element-pair form works in some Maestro versions (useful for drag-and-drop) but is not in the current official reference — test before relying on it, and fall back to coordinate `start:` + `end:` derived from the two elements if needed.

### back

Press the system back button. Android hardware back; on iOS, attempts a swipe-from-left-edge gesture.

```yaml
- back
```

**Flutter iOS caveat**: `- back` is **unreliable** on Flutter iOS, especially with `go_router` or custom AppBars — it often silently no-ops. Tap the AppBar chevron instead: `- tapOn: "Back"` (the Material back icon exposes `accessibilityText: "Back"`). See `references/flutter.md` Gotcha #6.

### pressKey

```yaml
- pressKey: "Enter"                     # case-insensitive
- pressKey: "Backspace"
- pressKey: "Home"
- pressKey: "Back"
- pressKey: "Volume up"
- pressKey: "Volume down"
- pressKey: "Power"
- pressKey: "Tab"
- pressKey: "Remote Up"                 # TV/tvOS
- pressKey: "Remote Down"
- pressKey: "Remote Left"
- pressKey: "Remote Right"
- pressKey: "Remote Center"
```

Common keys also accept lowercase aliases (`enter`, `backspace`). On **Flutter iOS**, `pressKey: "Enter"` is the reliable way to dismiss the keyboard from a single-line TextField.

---

## Text input

### inputText

Types into the currently focused element. Tap the field first if nothing is focused.

```yaml
- tapOn:
    id: "email_field"
- inputText: "user@example.com"
- inputText: "${USERNAME}"               # env/JS variable substitution
```

**Limitations:**
- No multiline typing. Literal `\n` becomes a newline on some platforms, but behavior is inconsistent. Prefer separate `inputText` + `pressKey: "Enter"`.
- Tab characters don't switch fields — tap the next field explicitly:
  ```yaml
  - tapOn:
      id: "next_field"
  ```

### inputRandomText / inputRandomEmail / inputRandomNumber / inputRandomPersonName

Convenient fixtures for filling forms:

```yaml
- inputRandomText
- inputRandomEmail                      # e.g. "zmoqt7@example.com"
- inputRandomNumber:
    length: 6
- inputRandomPersonName                 # e.g. "Alice Johnson"
```

### eraseText

Delete N characters from the currently focused field. Default erases ~50 chars.

```yaml
- eraseText                             # default
- eraseText: 10                         # delete 10 chars
```

### hideKeyboard

Dismiss the soft keyboard.

```yaml
- hideKeyboard
```

**Fails on Flutter iOS** with *"Couldn't hide the keyboard…"*. On Flutter iOS use `- pressKey: "Enter"` instead.

### setClipboard

Put a literal string on the device clipboard. Useful before `pasteText`.

```yaml
- setClipboard: "Hello from clipboard"
- setClipboard: "${SECRET_TOKEN}"
```

### pasteText

Paste from the device clipboard into the focused field.

```yaml
- tapOn:
    id: "message_field"
- pasteText
```

### copyTextFrom

Copy the text of a visible element into the JS variable `maestroCopiedText`.

```yaml
- copyTextFrom: "Order #"               # shorthand text selector
- copyTextFrom:
    id: "order_number"
- assertTrue: ${maestroCopiedText.length > 0}
```

**Flutter caveat**: `copyTextFrom` reads the `text` attribute, which is **empty for Flutter `Text` widgets** (their content lives in `accessibilityText`). Calling `copyTextFrom` on a `Text`-backed element yields `undefined`. `TextField` / `TextFormField` are exceptions — their `text` attribute DOES hold the live input value, so `copyTextFrom` works on inputs. For label readouts, rewrite as `assertVisible` with an explicit `text:` regex, or expose the value via HTTP and fetch with `runScript`.

---

## Scrolling

### scroll

Scrolls the currently focused scrollable by one viewport, vertically. No options.

```yaml
- scroll
- scroll
- scroll
```

### scrollUntilVisible

Scroll repeatedly until the target element is visible OR timeout hits.

```yaml
- scrollUntilVisible:
    element:                            # a selector map (or shorthand string)
      id: "item_42"
    direction: DOWN                     # default DOWN; also UP | LEFT | RIGHT
    timeout: 20000                      # ms, default 20000
    speed: 40                           # 0-100, higher = faster. Docs say default 40
    visibilityPercentage: 100           # 0-100. How much of element must be visible. Default 100
    centerElement: false                # default false. true = keep scrolling until element is ≥30% from the viewport edge
```

**Flutter tuning**: empirically, long `ListView.builder` lists often miss targets with the default settings — items in the cacheExtent appear as 1-pixel strips at the screen edge and satisfy `visibilityPercentage: 100` without the scroll actually moving them into view (see `references/flutter.md` Gotchas #8 and #9). Use `visibilityPercentage: 50` to accept partially-visible as "found", and `centerElement: true` to force a real scroll:

```yaml
- scrollUntilVisible:
    element:
      id: "item_42"
    direction: DOWN
    speed: 40
    visibilityPercentage: 50
    centerElement: true
```

---

## Assertions

### assertVisible

Verify an element is visible on screen. Retries until default timeout (~10s).

```yaml
- assertVisible: "Welcome back!"        # shorthand
- assertVisible:
    id: "success_banner"
    text: "^Logged in$"                 # both id AND text must match (regex)
    enabled: true
```

### assertNotVisible

Fail if the element IS visible. Useful for verifying something disappeared.

```yaml
- assertNotVisible: "Loading…"
- assertNotVisible:
    id: "error_toast"
```

### assertTrue

Evaluate a JavaScript expression. Must yield truthy.

```yaml
- assertTrue: ${maestroCopiedText === "3"}
- assertTrue: ${output.counter > 5}
- assertTrue: ${/^order-\d+$/.test(output.id)}
```

### assertWithAI (beta)

Use an LLM to verify complex UI state with natural language. Useful for visual patterns that are awkward to express as selectors (e.g. "a two-factor prompt with 6 digit boxes is visible").

```yaml
- assertWithAI: "The product price is highlighted in red"
- assertWithAI:
    assertion: "The checkout button is enabled and large"
    optional: true                      # default true — AI flakiness won't fail the flow
```

`optional: true` is the **default** (and recommended) so LLM nondeterminism doesn't break CI. Set `optional: false` only when the assertion is the actual subject of the test.

### extractTextWithAI (beta)

Capture the current screen and have the LLM extract a specified piece of text into a variable. Useful for CAPTCHA, dynamic labels, screens where OCR-ish extraction is needed.

```yaml
# Shorthand form — result stored in ${aiOutput}
- extractTextWithAI: "CAPTCHA value shown in the image"
- inputText: ${aiOutput}

# Full form
- extractTextWithAI:
    query: "First item title"
    outputVariable: "firstTitle"        # default "aiOutput"
    optional: false                     # default true — set false to fail the flow on extraction failure
- tapOn: "${firstTitle}"
```

Like `assertWithAI`, this is LLM-backed and nondeterministic — don't use it as a substitute for deterministic selectors when they're available.

### assertNoDefectsWithAI (beta)

AI-driven visual defect detection. Flags overlapping text, clipped content, etc.

```yaml
- assertNoDefectsWithAI
```

### assertScreenshot

Visual regression — compare current screen against a baseline PNG stored at `path:`. Create the baseline with a `takeScreenshot: "path/foo"` in an earlier run.

```yaml
- assertScreenshot: "baselines/home_screen.png"      # shorthand = path
- assertScreenshot:
    path: "baselines/cart_with_items.png"             # required — baseline image location
    cropOn:                                           # optional — focus comparison on one element
      id: "banner"
    thresholdPercentage: 98                           # default 95. Higher = stricter match
    label: "Home screen pixel check"                  # optional — appears in test output
```

Raising `thresholdPercentage` (e.g. 98) is stricter; lowering (e.g. 90) tolerates more variation. Fails if the baseline doesn't exist yet — run `takeScreenshot` first to create it.

---

## Waiting

### waitForAnimationToEnd

Block until screen stops changing. Use after navigation or any animated state change.

```yaml
- waitForAnimationToEnd
- waitForAnimationToEnd:
    timeout: 5000                       # ms, default 5000
```

### extendedWaitUntil

Wait up to N ms for a selector to become (not) visible. More powerful than a bare `assertVisible` when you need a specific timeout.

```yaml
- extendedWaitUntil:
    visible:
      id: "success_banner"
    timeout: 15000                      # ms, required
- extendedWaitUntil:
    notVisible: "Loading…"
    timeout: 10000
```

---

## Flow control

### runFlow

Run a subflow file, optionally with overridden env.

```yaml
- runFlow:
    file: "subflows/login.yaml"
    env:
      EMAIL: "user@test.com"
      PASSWORD: "secret"
```

Also used for **conditionals** (no file, inline `commands:`):

```yaml
- runFlow:
    when:
      visible: "Cookie banner"          # selector
      notVisible: "Already dismissed"   # selector
      platform: iOS                     # iOS | Android | Web
      true: ${output.flag === 1}        # JS expression
    commands:
      - tapOn: "Accept"
```

All `when:` conditions AND together. Set only the ones that matter.

**Env priority with `runFlow`**: values passed in `env:` to a subflow override both the parent flow's env and the CLI `-e` params. In other words, **subflow constants win over parameters with the same name**. Use this to pin a known value in a specific subflow invocation.

### runScript

Run an external JavaScript file. The script can read/write `output.*` and make HTTP calls via `http.get/post`.

```yaml
- runScript: scripts/fetch_token.js
- runScript:
    file: scripts/generate_user.js
    env:
      ENDPOINT: "https://api.test"
```

### evalScript

Inline JavaScript. Use the `${...}` inline form for assignments you want to read back later.

```yaml
- evalScript: ${output.name = 'Alice'}    # assignment in inline form — persists
```

**Block form is a trap — don't use it for anything that writes `output`.** The multi-line `|` block appears to run in a separate JS context; `output.*` writes do NOT propagate to the flow's template substitution. Use `runScript: scripts/setup.js` for multi-statement logic instead — it writes to the same `output` the flow reads.

```yaml
# Looks innocent. Does NOT work — output.timestamp stays undefined.
- evalScript: |
    output.timestamp = new Date().toISOString();
    output.id = Math.floor(Math.random() * 10000);

# Use runScript instead
- runScript: scripts/set_timestamps.js
```

**JS runtime available globals:**
- `output` — object persisting across the flow. Use for variables.
- `maestroCopiedText` — the most recent `copyTextFrom` result (string or undefined).
- `http` — `http.get(url)`, `http.post(url, body)`, returns `{ok, statusCode, body}`.
- `console.log()` — logs to Maestro's stdout.
- Standard ES5-ish JavaScript (Nashorn/GraalJS under the hood on JVM). Avoid ES6+ arrow functions and template literals if portability matters.

### repeat

```yaml
# Fixed iterations
- repeat:
    times: 5
    commands:
      - tapOn: "Like"
      - waitForAnimationToEnd

# Loop while a condition holds — pagination, "Load more", etc.
- repeat:
    while:                              # condition — any selector map or JS via true:
      visible: "Load more"
    commands:
      - tapOn: "Load more"

# Smart loop: both times and while — the `times:` is a hard cap that guarantees
# the loop terminates even if the while condition never becomes false
# (e.g. an endless feed). `times` acts as a safety net.
- repeat:
    while:
      visible: "Load more"
    times: 20                            # stop after 20 iterations no matter what
    commands:
      - tapOn: "Load more"
      - waitForAnimationToEnd           # settle between iterations
```

**Caveat for `times:`**: `${output.x}` substitution from `evalScript` may not resolve in time — Maestro then interprets `times:` as "repeat indefinitely" and hangs. Prefer `env:` frontmatter variables:

```yaml
env:
  N: 5
---
- repeat:
    times: ${N}           # reliable
    commands: [...]
```

### retry

Rerun a block up to N times on failure.

```yaml
- retry:
    maxRetries: 3
    commands:
      - tapOn:
          id: "flaky_button"
      - assertVisible: "Next screen"
```

---

## Device configuration

### setLocation

GPS simulation.

```yaml
- setLocation:
    latitude: 37.7749
    longitude: -122.4194
```

### setOrientation

```yaml
- setOrientation: PORTRAIT
- setOrientation: LANDSCAPE_LEFT
- setOrientation: LANDSCAPE_RIGHT
- setOrientation: PORTRAIT_UPSIDE_DOWN
```

### setPermissions

Set app permissions without relaunching.

```yaml
- setPermissions:
    camera: allow                       # allow | deny | unset | always | whenInUse
    location: always
    contacts: deny
    notifications: allow
```

### setAirplaneMode / toggleAirplaneMode

```yaml
- setAirplaneMode: enabled              # enabled | disabled
- toggleAirplaneMode
```

### travel

Simulate time change. Values are absolute dates (ISO 8601).

```yaml
- travel: "2030-01-01T00:00:00Z"
```

---

## Media and recording

### takeScreenshot

```yaml
- takeScreenshot: "home_before_login"   # filename (no extension)
# Saved to test output dir, or to --debug-output/... if set
```

### startRecording / stopRecording

Video recording of the run. Saves MP4 to the output dir.

```yaml
- startRecording: "login_flow"
- # ... commands ...
- stopRecording
```

### addMedia

Inject images/videos into the device photo library — useful for testing media pickers.

```yaml
- addMedia:
    - "fixtures/photo1.jpg"
    - "fixtures/video1.mp4"
```

---

## Deep links

### openLink

Open a URL. If the app handles the scheme/host, it deep-links; otherwise falls back to browser.

```yaml
- openLink: "myapp://product/42"
- openLink:
    link: "https://example.com/checkout?id=${output.id}"
    autoVerify: true                    # Android: include auto-verified links
    browser: false                      # force in-app even if browser would otherwise open
```
