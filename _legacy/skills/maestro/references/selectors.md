# Maestro selectors reference

Load this when:
- You know the command but are unsure how to match the element.
- You have multiple similar elements and need to disambiguate.
- Your flow taps the wrong thing and you need to understand why.

## The mental model

A selector is a **filter** that Maestro runs against the current screen's accessibility tree to pick one element. Every command that acts on elements (`tapOn`, `assertVisible`, `longPressOn`, `scrollUntilVisible.element`, `copyTextFrom`, …) takes the same selector grammar.

If more than one element matches, Maestro takes the first unless you constrain further. Use `index:` or add more fields to narrow down.

## Shorthand vs full form

Every action command accepts:

```yaml
- tapOn: "Submit"                     # shorthand: matches text/accessibilityText/hint/id by regex
- tapOn:
    text: "Submit"                    # full form: explicit attribute
```

The shorthand searches a broader set of attributes than the full `text:` form — that's why `tapOn: "Login"` finds a button whose only textual content is an `accessibilityLabel`. The full `text:` only matches the `text` attribute (which is empty on Flutter).

**Always prefer full-form with `id:` when you have a stable identifier.** It's unambiguous and robust.

## Core selectors

### `text:` — regex against text content

Matches against the `text` attribute (and, empirically, behaves like a full-match not substring). Special chars (`$`, `.`, `*`, `(`, `[`, `\`, `+`, `?`, `{`, `}`, `|`) must be escaped.

```yaml
- tapOn:
    text: "^Sign In$"                 # exact match
- tapOn:
    text: ".*Continue.*"              # substring match (. doesn't match newline)
- tapOn:
    text: "(?s).*Multi\\nline.*"      # DOTALL flag — . matches newlines
- tapOn:
    text: "\\$[0-9]+"                 # escape literal $
- tapOn:
    text: "Delete\\?"                 # escape literal ? — otherwise "Delete" alone matches
```

**Key rules:**
- Full-match by default — the whole attribute value must match.
- `.` does not match `\n`. Use `(?s)` inline flag for DOTALL.
- Case-sensitive. Use `(?i)` inline flag for case-insensitive.
- Escape special regex characters with `\\` (YAML requires double-backslash to represent a single backslash).

### Regex metachars that appear in normal UI copy

These are the ones that bite most often. Scan every user-facing string you selector on for these and escape them with `\\`:

| Char | Seen in UI copy as        | Regex meaning                            | Escape to       |
|------|---------------------------|------------------------------------------|-----------------|
| `?`  | "Are you sure?"           | Makes prior char optional                | `\\?`           |
| `.`  | "$4.99", "v1.2.3"         | Any single char (not newline)            | `\\.`           |
| `$`  | "$10", "USD$"             | End of string                            | `\\$`           |
| `(` `)` | "(required)"          | Group                                    | `\\(` `\\)`     |
| `*`  | "Required*"               | Zero or more of prior                    | `\\*`           |
| `+`  | "+1 (415) 555-…"          | One or more of prior                     | `\\+`           |
| `[` `]` | "[beta]"              | Character class                          | `\\[` `\\]`     |
| `|`  | "Save | Cancel"           | Alternation                              | `\\|`           |

When in doubt, prefer `id:` — it's literal, not regex, so none of this matters.

### `id:` — identifier match

Android: `android:id` / Jetpack Compose `testTag`.
iOS: `accessibilityIdentifier`.
Flutter: `Semantics(identifier: '...')`.

```yaml
- tapOn:
    id: "login_button"                # literal match in practice
- tapOn:
    id: "login_.*"                    # also interpreted as regex (use sparingly)
```

Maestro internally stores `id:` as a regex pattern (the `--debug-output` dumps show `idRegex` in the commands log). In practice, treat it as literal — use the exact identifier your app sets — but be aware that accidental regex metacharacters in your identifier string (e.g. `.` or `*`) will be interpreted as regex if present. Stable identifiers should use alphanumerics and underscores to avoid surprises.

### `index:` — pick Nth match

Zero-based. Only meaningful when the other selector criteria match multiple elements.

```yaml
- tapOn:
    id: "list_row"
    index: 2                          # third occurrence
```

### `point:` — screen coordinates

Percentage or absolute pixels. Fragile — only use when no other selector works.

```yaml
- tapOn:
    point: "50%,50%"                  # center of screen
- tapOn:
    point: "100,250"                  # absolute pixel coordinates
```

## State selectors

Filter by widget state. Combine with other fields — all must match.

```yaml
- tapOn:
    text: "Next"
    enabled: true                     # button must be enabled
- assertVisible:
    id: "remember_me"
    checked: false                    # checkbox must be unchecked
- tapOn:
    id: "field_1"
    focused: true                     # element must have focus
- assertVisible:
    id: "tab_home"
    selected: true
```

## Relational selectors

Find an element based on its relationship to another. Useful when the target has no unique text/id.

```yaml
# Positional — nearest element in that direction
- tapOn:
    text: "Delete"
    below:
      text: "Recent files"

- tapOn:
    above:
      id: "footer"

- tapOn:
    leftOf:
      id: "notifications_icon"

- tapOn:
    rightOf:
      text: "Name"
```

### Hierarchy — `containsChild`, `containsDescendants`, `childOf`

```yaml
# containsChild — parent with a direct child matching
- tapOn:
    id: "card"
    containsChild:
      text: "Active"

# containsDescendants — parent whose subtree contains ALL listed selectors
- assertVisible:
    id: "product_row"
    containsDescendants:
      - text: "In stock"
      - text: "Free shipping"

# childOf — child of a specific parent
- tapOn:
    text: "Edit"
    childOf:
      id: "profile_section"
```

## `optional:` — don't fail if not found

```yaml
- tapOn:
    text: "Dismiss cookie notice"
    optional: true                    # skip silently if absent
```

## Dimension matchers

Useful for assertions on icon sizes, image thumbnails, specific banner dimensions.

| Field       | Meaning                                                  |
|-------------|----------------------------------------------------------|
| `width`     | Exact pixel width                                        |
| `height`    | Exact pixel height                                       |
| `tolerance` | ± pixels allowed when matching `width` / `height` (handles device-pixel-ratio variation — typical value 2-5) |

```yaml
- assertVisible:
    id: "avatar"
    width: 48
    height: 48
    tolerance: 2                      # accepts 46-50 px
```

Rendering engines and screen scaling routinely produce 1-2 pixel variation in reported dimensions across devices. Use `tolerance` whenever you assert a dimension across more than one device.

## Element traits

Match elements by inherent shape/content rather than text or id.

| Trait       | Matches                                                                 |
|-------------|-------------------------------------------------------------------------|
| `text`      | Any element with non-empty text or accessibility label (content-agnostic) |
| `long-text` | Elements whose text exceeds ~200 characters — good for "did the feed load?" checks |
| `square`    | Elements where `width` and `height` are within 3% of each other — icons, avatars |

```yaml
# Tap a square icon to the right of the "Home" label
- tapOn:
    traits:
      - square
    rightOf:
      text: "Home"

# Assert the article body (long paragraph) has loaded
- assertVisible:
    traits:
      - long-text
```

Traits shine when you can't rely on a stable text/id — for generic or dynamically-generated UI.

## Regex reference (quick)

Maestro uses Java regex (via `java.util.regex.Pattern`).

| Want                              | Pattern                       |
|-----------------------------------|-------------------------------|
| Exact match "Hello"               | `Hello` (full-match is the default) or `^Hello$` for emphasis |
| Contains "Hello"                  | `.*Hello.*`                   |
| Contains across newlines          | `(?s).*Hello.*`               |
| Case-insensitive contains         | `(?i).*hello.*`               |
| Starts with "Hello"               | `^Hello.*`                    |
| Ends with "Hello"                 | `.*Hello$`                    |
| Literal `$10`                     | `\\$10` (YAML needs `\\`)     |
| Literal `Are you sure?`           | `Are you sure\\?`             |
| Digits only                       | `^[0-9]+$`                    |
| Dollar amount                     | `\\$[0-9]+\\.?[0-9]*`         |

## Picking the right selector: decision flow

1. **Is there an id?** Use `id:`. Done.
2. **Unique visible text that's a single line?** Use shorthand `tapOn: "The text"` (convenient) or full `text: "^The text$"` (explicit).
3. **Text spans multiple lines (typical of Flutter ListTile)?** Use DOTALL `text: "(?s).*needle.*"` — or add `Semantics(identifier:...)` to the app.
4. **Multiple matches?** Narrow with `index:`, `containsChild:`, or relational selectors (`below:`, `childOf:`).
5. **Transient/animated element?** Wrap the selector in `extendedWaitUntil`.
6. **Truly no unique attribute?** Last resort: `point: "x%,y%"`.

## Combining selectors

All fields in a selector map are ANDed together. There is no OR — achieve alternatives via `optional:` + multiple commands, or via `runFlow.when:`.

```yaml
# Element must be: tagged submit_btn AND visible text Submit AND enabled
- tapOn:
    id: "submit_btn"
    text: "Submit"
    enabled: true
```
