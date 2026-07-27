# JSON File Reference

Specification for SimPilot v2 files under `.simpilot/`.

## Common Rules

- Test ids use kebab-case.
- Run/result timestamps use ISO 8601 with timezone offset.
- Test steps use explicit objects. Natural-language action strings are not valid v2 specs.

## Directory Structure

```text
.simpilot/
  config.json
  tests/<id>.json
  suites/<name>.json
  runs/<run-id>/
    run.json
    summary.json
    trace.jsonl
    report.html
    <test-id>/
      result.json
      trace.jsonl
      step-NNN.png
      step-NNN.describe-before.json
      step-NNN.describe-after.json
  verify/<timestamp>_<description>/
    checks.json
    findings.json
    report.html
```

## config.json

```json
{
  "app": "com.example.myapp",
  "step-delay": 0.3,
  "max-retries": 1,
  "network-condition-provider": "/absolute/path/to/provider",
  "build": { "project": "MyApp.xcodeproj", "scheme": "MyApp" }
}
```

Fields:

| Field | Type | Required |
|---|---|:---:|
| `app` | string | Yes |
| `step-delay` | number | No |
| `max-retries` | int | No |
| `keep-runs` | int | No |
| `record-video` | bool | No |
| `network-condition-provider` | absolute path string | No |
| `build` | object (`project` / `scheme` / `configuration`) | No |

The harness (`run-test` / `run-suite`) consumes only `app`, `step-delay`, and `max-retries`. `build` is load-bearing for the build step (see `../../sipi-common/docs/build.md`; all sub-keys are optional, and an empty `"build": {}` enables auto-detection). `keep-runs` and `record-video` are accepted by `sipi validate` but are not acted on by the deterministic runner.

## tests/<id>.json

```json
{
  "id": "login-flow",
  "title": "Login Flow",
  "tags": ["smoke"],
  "steps": [
    {
      "id": "tap-sign-in",
      "action": {
        "type": "tap",
        "selector": { "id": "auth.sign-in" }
      },
      "verify": {
        "contains": ["Dashboard"],
        "absent": ["Sign In"]
      },
      "wait": 3
    }
  ]
}
```

Top-level fields:

| Field | Type | Required |
|---|---|:---:|
| `id` | string | Yes |
| `title` | string | Yes |
| `app` | string | No |
| `tags` | string[] | No |
| `steps` | Step[] | Yes |
| `created` | string | No |
| `updated` | string | No |

Step fields:

| Field | Type | Required |
|---|---|:---:|
| `id` | string | No |
| `action` | Action | No* |
| `verify` | Verify | No* |
| `optional` | bool | No |
| `wait` | number | No |
| `note` | string | No |

\* At least one of `action` or `verify` is required.

## Action

`tap` with selector:

```json
{ "type": "tap", "selector": { "id": "tab.settings" } }
```

`tap` with coordinate:

```json
{ "type": "tap", "point": { "x": 0.5, "y": 0.8, "unit": "norm" } }
```

`type` (the field must already be focused — tap it first):

```json
{ "type": "type", "text": "hello@example.com" }
```

By default `type` enters text by pasting it through the simulator pasteboard
(Cmd+V), which is independent of the guest keyboard layout and input language —
far more reliable than keystroke injection. Add `"input-method": "keyboard"` only
for a field that must receive real per-character keystrokes; keyboard mode
supports US-keyboard characters only and is rejected for accented/non-Latin/emoji
text. Pasting clobbers and best-effort restores the simulator pasteboard (which is
synced with the Mac pasteboard, so the host clipboard is transiently replaced too).

```json
{ "type": "type", "text": "1234", "input-method": "keyboard" }
```

Both methods insert at the caret, so a field that already holds text keeps it and
ends up with both strings — including leftovers from an earlier step or a previous
run. Add `"clear": true` to select all (Cmd+A) and delete before inserting, which
makes the field's resulting value depend only on `text`. Prefer it for any step
whose `verify` asserts the exact field contents. `clear` reaches committed text
only: an IME's in-progress composition is not part of the field value yet and
survives a select-all. `clear` rides on the same keyboard path as `type` itself,
so it is equally ineffective where keyboard HID is not delivered (iOS 27.0) — use
`set-text` there, which replaces the whole value and needs no clear.

```json
{ "type": "type", "text": "replaced", "clear": true }
```

`set-text` — write a field's content WITHOUT typing (targets the element like `tap`:
exactly one of `selector` / `point`, plus `text`):

```json
{ "type": "set-text", "selector": { "id": "login.email" }, "text": "user@example.com" }
```

`set-text` sets the element's accessibility value directly, so it needs no keyboard,
no pasteboard, and no focus, and it carries any text (Japanese, emoji) regardless of
the guest keyboard layout or IME. It is the only text-entry action that works on a
runtime that does not deliver keyboard HID (iOS 27.0 simulators today, where `type`
silently enters nothing). The write is confirmed against a fresh read of the app, so
the step FAILS when the value did not take — only editable text elements accept it.

Because nothing is typed, per-keystroke behaviour is not exercised (`onChange` per
character, keyboard toolbars, autocomplete, IME composition). Choose per intent: use
`type` when the typing itself is under test, `set-text` when the field's content is
what matters.

Two constraints to plan around:

- The target must be **on screen**. The write goes through a hit-test at the element's
  activation point, so a field scrolled out of view (or hidden under the keyboard) has
  a frame but cannot be hit — scroll it into view first, exactly as before a `tap`.
- A field that deliberately reports something other than what was written fails the
  built-in confirmation. `SecureField` is the common case: the write lands (measured —
  an 11-character write reached the app) but its AXValue reads back as `•••••••••••`.
  Use `"verify-value": false` there and assert on the app's own output instead:

```json
{ "type": "set-text", "selector": { "id": "login.password" }, "text": "s3cret", "verify-value": false }
```

`"verify-value": false` records the step's method as `set-text…+unverified` in
`result.json`, so the artifact never implies a confirmation that did not happen. It
is the saved-test counterpart of the CLI's `sipi set-text --no-verify`.

`key`:

```json
{ "type": "key", "usage": 40 }
```

`button`:

```json
{ "type": "button", "button": "home" }
```

`swipe`:

```json
{
  "type": "swipe",
  "start": { "x": 0.5, "y": 0.8, "unit": "norm" },
  "end": { "x": 0.5, "y": 0.2, "unit": "norm" },
  "duration": 0.3
}
```

`wait`:

```json
{ "type": "wait", "duration": 1.0 }
```

### Extended actions

These drive the richer `sipi` primitives as deterministic, saved test steps.

`long-press` (selector or `point`; `duration` is the hold in seconds, default 0.5) — context menus, reorder handles:

```json
{ "type": "long-press", "selector": { "label": "Photo" }, "duration": 0.6 }
```

`slider` (requires `selector` with `id` or `label`, and `value` 0…100; optional `tolerance` normalized 0…1, default 0.02). Resolves the slider, drags the thumb, then polls AXValue — the step fails if it cannot reach the target:

```json
{ "type": "slider", "selector": { "label": "Volume", "element-type": "Slider" }, "value": 75 }
```

`gesture` (`preset` is one of `scroll-up`/`scroll-down`/`scroll-left`/`scroll-right`/`swipe-from-{left,right,top,bottom}-edge`; optional `duration`):

```json
{ "type": "gesture", "preset": "scroll-down" }
```

`drag` (interpolated point-to-point; `steps` 1…1000 default 60, `duration` default 0.6) — smoother/more reliable than `swipe`:

```json
{ "type": "drag", "start": { "x": 0.5, "y": 0.7 }, "end": { "x": 0.5, "y": 0.3 }, "steps": 60 }
```

`key-combo` (hold `modifiers` keycodes, press `key`, release in LIFO order) — e.g. Cmd+A (227,4):

```json
{ "type": "key-combo", "modifiers": [227], "key": 4 }
```

`key-sequence` (press+release each keycode in order; optional `delay` between presses, default 0.1s):

```json
{ "type": "key-sequence", "keycodes": [11, 8, 15, 15, 18], "delay": 0.1 }
```

`orientation` (`portrait` | `portrait-upside-down` | `landscape-left` | `landscape-right` | `face-up` | `face-down`):

```json
{ "type": "orientation", "orientation": "landscape-left" }
```

`crown` (Digital Crown rotation delta; Apple Watch simulators only):

```json
{ "type": "crown", "delta": 40 }
```

All keycodes are USB HID usage codes 0…255. `long-press`/`slider` selectors honor the same fast→deep resolution and `optional` skip as `tap`.

### Simulator-control actions

Open a deep link or universal link through the system:

```json
{ "type": "open-url", "url": "myapp://settings" }
```

Set permission state (`operation`: `grant`, `revoke`, or `reset`). `bundle-id` defaults to the test app; harness privacy actions are always app-scoped, including `reset all`:

```json
{ "type": "privacy", "operation": "revoke", "service": "photos" }
```

Send an inline Simulator remote notification. The payload must contain an `aps` object and encode to at most 4096 bytes:

```json
{ "type": "push", "payload": { "aps": { "alert": "New message" } } }
```

Set or clear location:

```json
{ "type": "location", "operation": "set", "latitude": 35.6812, "longitude": 139.7671 }
{ "type": "location", "operation": "clear" }
```

Change UI environment settings:

```json
{ "type": "appearance", "appearance": "dark" }
{ "type": "content-size", "content-size": "accessibility-large" }
{ "type": "increase-contrast", "enabled": true }
```

Override or clear screenshot-only status-bar values. `arguments` are passed as separate arguments to `simctl status_bar ... override`; they do not change actual connectivity or battery state:

```json
{ "type": "status-bar", "operation": "override", "arguments": ["--time", "9:41", "--batteryLevel", "100"] }
{ "type": "status-bar", "operation": "clear" }
```

Restart or terminate an app. Launch environment keys omit the `SIMCTL_CHILD_` prefix; SimPilot adds it safely:

```json
{ "type": "launch", "arguments": ["--fixture"], "environment": { "API_MODE": "fixture" } }
{ "type": "terminate" }
```

Apply or clear a profile through the configured external provider:

```json
{ "type": "network-condition", "operation": "apply", "profile": "packet-loss-100" }
{ "type": "network-condition", "operation": "clear" }
```

`bundle-id` optionally overrides the configured app for `privacy`, `push`, `launch`, `terminate`, and `network-condition`. See `adverse-state-testing.md` for provider capability checks, cleanup, and the difference between request failure and `NWPathMonitor` path loss.

## Selector

Exactly one of:

```json
{ "id": "auth.sign-in" }
{ "label": "Sign In" }
{ "value": "42" }
```

Optional selector field:

| Field | Type | Description |
|---|---|---|
| `element-type` | string | Restrict match to an accessibility type such as `Button` or `Switch` |

## Point

```json
{ "x": 0.5, "y": 0.8, "unit": "norm" }
{ "x": 200, "y": 700, "unit": "pixel" }
```

`unit` is either `norm` (normalized 0...1, the default) or `pixel` (logical screen points — the same coordinate space as describe-ui `frame`, not device/retina pixels). `sipi validate` rejects any other `unit`, `norm` coordinates outside 0...1, and negative `pixel` coordinates.

## Verify

```json
{
  "contains": ["Settings"],
  "absent": ["Home only text"]
}
```

- `contains`: every string must appear in `describe-ui`.
- `absent`: every string must be absent from `describe-ui`.
- Use strings that prove the new state, not static chrome.

## suites/<name>.json

```json
{
  "name": "regression",
  "tests": ["app-launch", "settings-toggle"],
  "settings": {
    "stop-on-failure": false,
    "reset-between-tests": true
  }
}
```

Required: `name`, `tests` (array of test ids, each resolved to `<workspace>/tests/<id>.json`). Optional: `description`, `settings` (object with optional `stop-on-failure` (bool, default `false`) and `reset-between-tests` (bool, default `true`)). The file must be named `<name>.json` — `sipi validate` enforces that the filename matches `name`.

## result.json

The harness writes `result.json`; do not author it manually.

Important fields:

| Field | Type |
|---|---|
| `id` | string |
| `passed` | bool |
| `review` | bool |
| `duration` | number |
| `steps` | ResultStep[] |

Each result step may include:

- `passed`
- `duration`
- `action`
- `screenshot`
- `screenshots.before`
- `screenshots.after`
- `verify`
- `attempted-methods`
- `failure-type` — `action` (selector/element resolution failure, or a thrown step error) or `verify` (a verify row not satisfied after the wait deadline, or a verify-only step that failed). `sipi validate` also accepts `timeout`, but the current harness never emits it — a wait-deadline verify miss is reported as `verify`.
- `describe-ui-snapshot`
- `skipped`
- `note`

## summary.json

`summary.json` is the compact result for agents and CI:

```json
{
  "status": "fail",
  "run-id": "2026-06-26_104522_iphone16_abc1234",
  "started": "2026-06-26T10:45:22.123+09:00",
  "finished": "2026-06-26T10:46:12.456+09:00",
  "device": { "name": "iPhone 16 Pro", "runtime": "iOS 26.0", "udid": "..." },
  "counts": {
    "total": 1,
    "passed": 0,
    "failed": 1,
    "review": 0,
    "skipped": 0
  },
  "top-failures": [
    {
      "test": "login-flow",
      "step": 1,
      "failure-type": "verify",
      "action": "tap auth.sign-in",
      "missing": "contains: Dashboard",
      "screenshot": "login-flow/step-001.png"
    }
  ],
  "report": "report.html"
}
```

`status` is the gate field (`pass` | `fail` | `review` | `empty`; see [Status Display](#status-display)). `started`, `finished` (ISO 8601 with offset), `device`, and `report` are always present. In each `top-failures` entry `action` is always present (defaults to `(verify-only)` when the step has no action); `missing`/`verify`, `matched`, and `screenshot` appear only when applicable.

## Status Display

Two related but distinct status mappings (the badge is per step/test; `status` is the run-level gate).

**Per-step / per-test badge** (evaluated in this order):

1. `passed && skipped` → **SKIP**
2. else `!passed` → **FAIL**
3. else `review` → **REVIEW**
4. else → **PASS**

**Run-level `summary.json` `status`** (evaluated in this order — ordering matters: a failed step is `fail` even when a step is also marked review):

1. `failed > 0` → `fail`
2. else `review > 0` → `review`
3. else `total == 0` → `empty`
4. else → `pass`

(The verify skill's report uses a separate "All OK" / "Issues Found" pill driven by `findings.json`; that is a different command and is not this table — see `../../sipi-verify/docs/report.md`.)
