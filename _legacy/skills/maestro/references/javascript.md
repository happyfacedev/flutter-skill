# JavaScript in Maestro flows

Load this when writing flows that use `evalScript`, `runScript`, `assertTrue`, or any `${...}` template substitution that does more than a bare variable read.

## The three ways to run JS

1. **Inline `${...}` substitution** — evaluates an expression inside the flow's JS context and inserts the result as a string.
2. **`evalScript: ${...}`** — runs a single JS expression. Same context as substitutions.
3. **`runScript: path/to/file.js`** — runs a multi-statement JS file. Modifies `output`.

The `evalScript: |` block (multi-line) form appears to run in a *separate* context — changes to `output` do NOT propagate back to the flow's template context. **Do not use block form for anything that needs to be read later.** Use inline or runScript instead.

## Runtime

Nashorn/GraalJS on the JVM. Practical implications:
- ES5-ish syntax works fine.
- ES6+ features (arrow functions, template literals, `let`/`const`) may work but are not guaranteed — prefer ES5 for portability.
- No `require`/`import` — each runScript file is a standalone script.
- No Node.js APIs (`fs`, `process`, etc.).

## Available globals

Inside any script (evalScript inline, runScript file, assertTrue expression):

| Global               | Type                              | Purpose                                        |
|----------------------|-----------------------------------|------------------------------------------------|
| `output`             | plain object, initially `{}`      | Persistent scratch space across the flow       |
| `maestroCopiedText`  | string / undefined                | Last `copyTextFrom` result                     |
| `http`               | object with `get`/`post`/`put`/`delete` | Simple HTTP client                       |
| `console`            | object with `log`                 | Logs to Maestro stdout                         |
| env vars             | as JS variables (no prefix)       | Every flow `env:` entry, every CLI `-e` param, every built-in below |

### Built-in env vars

Maestro injects these automatically — available both as `${NAME}` template substitution and as JS globals:

| Variable               | Meaning                                           |
|------------------------|---------------------------------------------------|
| `MAESTRO_FILENAME`     | Current flow filename (without extension)         |
| `MAESTRO_DEVICE_UDID`  | Device / simulator UDID                           |
| `MAESTRO_SHARD_ID`     | Shard number (1-based) when using `--shards`      |
| `MAESTRO_SHARD_INDEX`  | Shard index (0-based)                             |

### Shell env capture

Any shell env var whose name starts with `MAESTRO_` is auto-captured into the flow — useful for CI secrets:

```bash
export MAESTRO_API_TOKEN=xyz
maestro test flow.yaml
# ${MAESTRO_API_TOKEN} is now available inside the flow
```

### CLI params arrive as strings

Values passed via `-e FOO=42` arrive as JS strings. If you need a number or boolean, convert:

```yaml
- evalScript: ${output.count = parseInt(FOO)}
- assertTrue: ${output.count > 10}
```

### Default values via JS `||`

```yaml
- inputText: ${USERNAME || "guest@test.com"}
- assertVisible: ${MESSAGE || "Welcome"}
```

### Env priority / override rules

Highest priority wins on a name collision:

1. CLI `-e` parameters
2. Subflow's own frontmatter `env:` block (defines the variable for that flow — **wins over runFlow.env**)
3. `runFlow.env:` values passed in by the parent
4. Parent flow's frontmatter `env:` block (inherited)
5. Workspace `config.yaml` `env:` block

**Counterintuitive — the subflow's own frontmatter `env:` SHADOWS values passed in via `runFlow.env:`.** Empirically verified on Maestro 2.4: a subflow `login.yaml` with frontmatter `env: { EMAIL: admin@x }` will always sign in as admin@x, even when called via `runFlow: { file: login.yaml, env: { EMAIL: other@y } }`. The runFlow value is silently ignored.

**Practical rule**: if you want a subflow to be parameterizable by `runFlow.env:`, **omit `env:` from its frontmatter entirely** and just let `${VAR}` resolve from the caller's environment. Reserve frontmatter `env:` for variables the subflow always wants to pin.

```yaml
# subflows/sign_in.yaml — parameterizable, NO frontmatter env defaults
appId: ${MAESTRO_APP_ID}
---
- inputText: ${EMAIL}        # resolves from runFlow.env or inherited parent env
- inputText: ${PASSWORD}
```

```yaml
# parent flow — passes env explicitly
- runFlow:
    file: subflows/sign_in.yaml
    env:
      EMAIL: maestro-noprofile@example.test
      PASSWORD: ${MAESTRO_TEST_PASSWORD}
```

## `output` — the persistent bag

```yaml
# Set
- evalScript: ${output.userId = 42}
- runScript: scripts/compute_checksum.js    # can modify output.* freely

# Read (template substitution)
- tapOn: "Order #${output.userId}"
- assertVisible: "Welcome user ${output.userId}"
- assertTrue: ${output.userId > 0}
```

Gotcha: **`evalScript: |` block form** does NOT persist changes. Always use inline `${...}` or runScript.

## HTTP from scripts

```javascript
// scripts/fetch_user.js
var resp = http.get('https://api.test/user/' + output.userId);
if (resp.ok) {
  var parsed = JSON.parse(resp.body);
  output.userName = parsed.name;
  output.userEmail = parsed.email;
} else {
  output.fetchFailed = true;
  output.fetchStatus = resp.status;
}
```

```yaml
- evalScript: ${output.userId = 42}
- runScript: scripts/fetch_user.js
- runFlow:
    when:
      true: ${!output.fetchFailed}
    commands:
      - assertVisible: "${output.userName}"
```

The `http` object is Maestro's own, **not** `fetch` or `axios`. Methods: `http.get(url)`, `http.post(url, {body: "..."})`, `http.put(...)`, `http.delete(...)`. Return shape: `{ok: boolean, status: number, body: string, headers: {...}}`.

## Env vars from frontmatter vs CLI

```yaml
# flow.yaml
appId: com.example.app
env:
  N: 5
  ENDPOINT: "https://api.test"
---
- tapOn: "${ENDPOINT}"     # uses defaults from env:
- repeat:
    times: ${N}
    commands:
      - tapOn: "Like"
```

```bash
# Override at the CLI — these win over frontmatter defaults
maestro test -e N=10 -e ENDPOINT="https://prod" flow.yaml
```

Inside JS, env vars are globals:

```yaml
- evalScript: ${output.scaled = N * 2}     # N is the env var
- assertTrue: ${output.scaled === 10}
```

## Template substitution where it works

`${...}` interpolation works in most string parameters:

| Works                              | Does NOT work                                  |
|------------------------------------|------------------------------------------------|
| `tapOn: "Hello ${NAME}"`           | Top-level YAML keys                            |
| `assertVisible: "${X}"`            | Structural keys like `retry:` when false       |
| `inputText: "${EMAIL}"`            | `times: ${output.x}` (use env var instead)     |
| `evalScript: ${output.a = 1}`      | `when:` — use `when: true: ${...}` instead     |
| `assertTrue: ${output.a > 0}`      |                                                |
| `id: "${PREFIX}_button"`           |                                                |

## `assertTrue` patterns

```yaml
- assertTrue: ${maestroCopiedText === "expected"}
- assertTrue: ${output.counter > 5}
- assertTrue: ${/^ORDER-\d+$/.test(maestroCopiedText)}   # regex test
- assertTrue: ${output.user && output.user.id}           # truthy chain
- assertTrue: ${output.items.length === 3}
- assertTrue: ${JSON.parse(maestroCopiedText).total > 0} # parse JSON from screen
```

Strict equality (`===`) is stricter than you might expect. If `${output.x}` is `"5"` (string) and you wrote `=== 5`, it's false. Either use `==`, convert with `parseInt(output.x)`, or be careful about types.

## Debug pattern: embed a variable in an assertion to inspect

If a substitution silently resolves to `undefined` and you're not sure why, make it fail loudly by embedding it in an assertion string:

```yaml
- assertVisible: "DEBUG_${output.suspect_var}_SENTINEL"
# On failure: "DEBUG_undefined_SENTINEL" is visible → now you know it's undefined
# On success: the embedded value is visible on screen as part of the assertion
```

This is faster than `console.log` (which goes to stdout) when you need to see a value fast.

## Generating synthetic data

```yaml
# From Maestro's built-in random input commands (no JS needed)
- inputRandomText
- inputRandomEmail
- inputRandomNumber:
    length: 6
- inputRandomPersonName

# From JS if you need more control
- evalScript: ${output.uuid = 'test-' + Math.floor(Math.random() * 1000000)}
- inputText: ${output.uuid}
```

## Common pitfalls

1. **Don't rely on `evalScript: |` multi-line blocks** — output doesn't persist. Use `runScript:` for anything multi-statement.
2. **`${output.x}` substitution in `times:` is unreliable** — use `env:` frontmatter + `${ENV_VAR}`.
3. **Types matter in `assertTrue`** — always `parseInt()` / `parseFloat()` numeric values from strings.
4. **`http` is not Node's fetch/axios** — different API surface; check return shape before assuming.
5. **`console.log` output goes to Maestro's stdout**, not visible in the normal test progress dots — add `--verbose` to see.
