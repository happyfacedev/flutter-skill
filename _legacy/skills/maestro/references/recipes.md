# Maestro recipes

Ready-to-adapt flow patterns. Copy the closest match, swap in your app's `appId` and selectors, and go. Each recipe includes a short note on when and why.

## Login (happy path)

```yaml
appId: com.example.app
---
- launchApp:
    clearState: true
- tapOn:
    id: "login_email_field"
- inputText: "user@test.com"
- tapOn:
    id: "login_password_field"
- inputText: "correct-horse"
# Dismiss keyboard BEFORE tapping submit — submit may be below keyboard
- pressKey: "Enter"                   # Flutter iOS — or `- hideKeyboard` on native
- tapOn:
    id: "login_submit_button"
# Use extendedWaitUntil instead of bare assertVisible when the result is async
- extendedWaitUntil:
    visible:
      id: "home_welcome_banner"
    timeout: 10000
```

Why this shape: every element has an `id:` (stable across copy/localization changes), the keyboard dismissal is explicit, and we wait generously for the post-submit transition.

## Login (subflow with env)

`subflows/login.yaml`:
```yaml
appId: com.example.app
---
- tapOn:
    id: "login_email_field"
- inputText: "${EMAIL}"
- tapOn:
    id: "login_password_field"
- inputText: "${PASSWORD}"
- pressKey: "Enter"
- tapOn:
    id: "login_submit_button"
- extendedWaitUntil:
    visible:
      id: "home_welcome_banner"
    timeout: 10000
```

`flows/smoke.yaml`:
```yaml
appId: com.example.app
---
- launchApp:
    clearState: true
- runFlow:
    file: "subflows/login.yaml"
    env:
      EMAIL: "user@test.com"
      PASSWORD: "secret"
- assertVisible: "Inbox"
```

## Scroll-to-item in a long list

```yaml
- tapOn:
    id: "list_tab"
- scrollUntilVisible:
    element:
      id: "list_item_42"
    direction: DOWN
    timeout: 15000
    speed: 40                         # Flutter lazy list fix — slower = reliable
    visibilityPercentage: 50          # accept 50% visible as "found"
- tapOn:
    id: "list_item_42"
```

## Pull-to-refresh

```yaml
- swipe:
    start: "50%,25%"                  # start near top (below app bar)
    end: "50%,85%"                    # drag far enough to trigger
    duration: 800
- extendedWaitUntil:
    visible: "Refreshed"              # or the updated data
    timeout: 5000
```

## Infinite scroll / "load more"

```yaml
- repeat:
    while:
      visible: "Load more"
    commands:
      - tapOn: "Load more"
      - waitForAnimationToEnd
```

## Form with many inputs

```yaml
- tapOn:
    id: "form_name_field"
- inputText: "Alice"
- pressKey: "Enter"                   # dismiss keyboard between fields
- tapOn:
    id: "form_email_field"
- inputText: "alice@test.com"
- pressKey: "Enter"
- tapOn:
    id: "form_subscribe_switch"
- tapOn:
    id: "form_terms_checkbox"
# Scroll to submit — it may be below the fold
- scrollUntilVisible:
    element:
      id: "form_submit_button"
    direction: DOWN
    speed: 40
- tapOn:
    id: "form_submit_button"
# Scroll again if the result appears below submit
- scrollUntilVisible:
    element:
      id: "form_result_banner"
    direction: DOWN
    speed: 40
- assertVisible:
    id: "form_result_banner"
```

## Back navigation through a multi-step flow (Flutter iOS)

```yaml
- launchApp:
    clearState: true
- tapOn:
    id: "start"
- tapOn:
    id: "step1_next"
- assertVisible: "Step 2"
- tapOn:
    id: "step2_next"
- assertVisible: "Step 3"
# On Flutter iOS, the `- back` command often silently no-ops.
# Tap the AppBar chevron by its accessibility label instead.
- tapOn: "Back"
- assertVisible: "Step 2"
- tapOn: "Back"
- assertVisible: "Step 1"
- tapOn: "Back"
- assertVisible: "Home"
```

## Multi-branch wizard (3-way fork driven by env)

```yaml
# flows/wizard_entry.yaml
appId: com.example.app
env:
  BRANCH: "A"
---
- launchApp:
    clearState: true
- tapOn:
    id: "wizard_start"
- tapOn:
    id: "wizard_option_${BRANCH}"
- runFlow:
    when:
      true: ${BRANCH === 'A'}
    file: "branches/wizard_a.yaml"
- runFlow:
    when:
      true: ${BRANCH === 'B'}
    file: "branches/wizard_b.yaml"
- runFlow:
    when:
      true: ${BRANCH === 'C'}
    file: "branches/wizard_c.yaml"
- assertVisible: "Success"
```

Run with: `maestro test -e BRANCH=A flows/wizard_entry.yaml`. Shared `onFlowStart`/`onFlowComplete` hooks in the entry file apply to the whole run.

## Handling a dialog that may or may not appear

```yaml
- runFlow:
    when:
      visible: "Accept cookies"
    commands:
      - tapOn: "Accept"
```

Put this right after `launchApp` for onboarding/consent popups.

## Snackbars block taps below them

A `SnackBar` in Flutter sits at the bottom of the `Scaffold` on top of the content. While it's up (~4s by default), taps that overlap its area may not reach the widget underneath.

If your flow fires a snackbar then immediately tries to interact with content near the bottom (checkboxes, bottom buttons), insert a wait:

```yaml
- tapOn:
    id: "submit_without_acceptance"
- assertVisible: "(?s).*Please accept the terms.*"
# Wait for the snackbar to dismiss before tapping things beneath it
- extendedWaitUntil:
    notVisible: "(?s).*Please accept the terms.*"
    timeout: 8000
- tapOn:
    id: "terms_checkbox"          # now it actually registers
- tapOn:
    id: "submit"
```

Symptom if you skip the wait: the tap "completes" per Maestro's log but the widget's state doesn't change (e.g., checkbox stays unchecked, button click doesn't fire).

## Alert → bottom sheet → snackbar chain

```yaml
# Alert
- tapOn:
    id: "show_alert_btn"
- assertVisible: "Alert Title"
- tapOn: "OK"
- assertVisible:
    id: "status"
    text: "alert_dismissed"
# Bottom sheet
- tapOn:
    id: "show_sheet_btn"
- tapOn: "Share"
- assertVisible:
    id: "status"
    text: "sheet_share"
# Snackbar (fast-disappearing toast)
- tapOn:
    id: "show_snack_btn"
- assertVisible: "Saved!"             # grab it while it's up — default timeout catches it
```

## Swiping tabs

```yaml
- tapOn: "Tab Two.*"                  # Flutter TabBar merges "Tab Two\nTab 2 of 3"
- assertVisible: "Tab Two content"
- swipe:
    direction: LEFT                   # swipe left to go to the next tab
- assertVisible: "Tab Three content"
- swipe:
    direction: RIGHT
- assertVisible: "Tab Two content"
```

## Extracting a dynamic value (OTP / CAPTCHA / generated token) with AI

Use `extractTextWithAI` when the value you need is truly dynamic and can't be scraped via `text:` — e.g. an OTP code the user is meant to type back, a CAPTCHA, or a screenshot-rendered price.

```yaml
# Trigger the screen that shows the OTP
- tapOn:
    id: "request_otp_btn"
- extendedWaitUntil:
    visible: "Your code"
    timeout: 10000
# Have the LLM read the 6-digit code
- extractTextWithAI:
    query: "The 6-digit verification code shown on screen"
    outputVariable: "otp"
    optional: false                    # fail the flow if extraction fails
# Use it in the next step
- tapOn:
    id: "otp_input"
- inputText: ${otp}
- tapOn:
    id: "verify_btn"
- assertVisible: "Verified"
```

Prefer deterministic selectors over AI wherever possible — this is a last resort, not a default.

## Async data load (loading + result + error)

```yaml
# Trigger load
- tapOn:
    id: "refresh_btn"
# Wait for the final state (don't try to catch the transient spinner)
- extendedWaitUntil:
    visible:
      id: "data_list"
    timeout: 15000
- assertVisible:
    id: "data_list"
- assertNotVisible:
    id: "loading_spinner"
```

Don't race the spinner — by the time Maestro evaluates `assertVisible: spinner`, the data might already have loaded. Always assert the final state.

## Error path with retry

```yaml
- tapOn:
    id: "refresh_btn"
- runFlow:
    when:
      visible:
        id: "network_error_toast"
    commands:
      - tapOn: "Retry"
      - extendedWaitUntil:
          visible:
            id: "data_list"
          timeout: 10000
```

## Gesture playground: tap / double-tap / long-press / swipe / drag

```yaml
- tapOn:
    id: "gesture_target"
- doubleTapOn:
    id: "gesture_target"
- longPressOn:
    id: "gesture_target"
# Directional swipe on the element
- swipe:
    direction: LEFT
    from:
      id: "gesture_target"
# Drag-and-drop
- swipe:
    from:
      id: "drag_source"
    to:
      id: "drop_target"
    duration: 800
```

## Counter with `repeat` and dynamic count from JS

```yaml
- evalScript: |
    output.n = 5;
- repeat:
    times: ${output.n}
    commands:
      - tapOn:
          id: "increment_btn"
- assertVisible:
    id: "counter_value"
    text: "^5$"
```

Note: `times:` accepts substituted values like `${output.n}`. Make sure the value is a number, not a string, otherwise the repeat may misbehave.

## Deep link entry point

```yaml
- launchApp:
    clearState: true
- openLink: "myapp://product/42?ref=test"
- assertVisible: "Product 42"
```

## Permissions granted pre-launch

```yaml
- launchApp:
    clearState: true
    permissions:
      all: allow                      # short-circuit all permissions
      location: always                # finer control per-permission
```

No need to wait for system dialogs mid-flow — Maestro pre-grants before launch.

## Biometrics / FaceID (iOS simulator)

```yaml
- tapOn: "Sign in with FaceID"
- launchApp:                          # re-auth — only if app restarts
    appId: com.example.app
# FaceID success is simulated via a key combo on the simulator;
# Maestro doesn't wrap this. Instead, have a debug menu hook or mock it.
```

There's no first-class Maestro command for biometric approval. Best practice: put a debug-only bypass in your app (toggled with `launchArguments:`) and use Maestro to set the flag.

## Tag-based filtering

```yaml
# smoke.yaml
appId: com.example.app
tags:
  - smoke
---
# …commands…
```

```bash
maestro test --include-tags smoke .maestro/flows/
maestro test --exclude-tags slow .maestro/flows/
```

## Hooks: shared setup and teardown

```yaml
appId: com.example.app
onFlowStart:
  - launchApp:
      clearState: true
onFlowComplete:
  - takeScreenshot: "final_state"
---
# …commands…
```

## Data-driven flows via env

```bash
maestro test -e USER=alice -e ROLE=admin .maestro/flows/login.yaml
```

```yaml
appId: com.example.app
env:
  USER: defaultuser
  ROLE: member
---
- tapOn:
    id: "email_field"
- inputText: "${USER}@test.com"
- runFlow:
    when:
      true: ${ROLE === 'admin'}
    commands:
      - assertVisible: "Admin panel"
```

## Workspace config.yaml

Place at the flows directory root. Values apply to any flow without its own frontmatter.

```yaml
# .maestro/config.yaml
appId: com.example.app
---
name: Checkout test suite

flows:
  - subflows/login.yaml
  - flows/*.yaml

executionOrder:
  continueOnFailure: true
  flowsOrder:
    - smoke
    - regression

tags:
  - regression
```

## Full test command cheat sheet

```bash
# Single flow
maestro test flow.yaml

# All flows in a folder
maestro test .maestro/flows/

# Env vars
maestro test -e EMAIL=alice@test -e PASSWORD=secret flow.yaml

# Tags
maestro test --include-tags smoke .maestro/flows/
maestro test --exclude-tags slow,broken .maestro/flows/

# Debug output (screenshots + per-command logs)
maestro test --debug-output ./debug flow.yaml

# Skip driver reinstall (speeds up after first run)
maestro test --no-reinstall-driver flow.yaml

# Report
maestro test --format JUNIT --output report.xml flow.yaml
maestro test --format HTML --output report.html flow.yaml

# Syntax check only (no device needed)
maestro check-syntax flow.yaml

# Live hierarchy dump — your #1 debugging tool
maestro hierarchy
```
