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

The harness (`run-test` / `run-suite`) consumes `app`, `step-delay`, `max-retries`, and `network-condition-provider`. `build` is load-bearing for the build step (see `../../sipi-common/docs/build.md`; all sub-keys are optional, and an empty `"build": {}` enables auto-detection). `keep-runs` and `record-video` are accepted by `sipi validate` but are not acted on by the deterministic runner.

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

`type` — keystroke-level entry, for steps where the TYPING is the subject
(per-character `onChange`, keyboard toolbar, candidate bar, Return/submit). For
simply putting content in a field, use `set-text` below instead. The field must
already be focused (tap it first):

```json
{ "type": "type", "text": "hello@example.com" }
```

By default `type` pastes through the simulator pasteboard (Cmd+V), which is
independent of the guest keyboard layout and input language. Add
`"input-method": "keyboard"` only for a field that must receive real per-character
keystrokes; keyboard mode supports US-keyboard characters only and is rejected for
accented/non-Latin/emoji text. Pasting clobbers and best-effort restores the
simulator pasteboard (which is synced with the Mac pasteboard, so the host
clipboard is transiently replaced too).

```json
{ "type": "type", "text": "1234", "input-method": "keyboard" }
```

Both methods insert at the caret, so a field that already holds text ends up with
both strings — including leftovers from an earlier step or a previous run. Add
`"clear": true` to select all (Cmd+A) and delete before inserting.

```json
{ "type": "type", "text": "replaced", "clear": true }
```

`type` confirms it did something: it compares the text fields' contents before and
after the insertion and FAILS the step when nothing changed, so a simulator that
has stopped delivering keyboard events can no longer produce a green step over an
empty field. Set
`"verify-effect": false` for the rare field whose insertion is genuinely
invisible.

The comparison is against the field as it stands AFTER any `clear`, so the two
idioms that end where they started still pass: `"clear": true` with the same
string, and clearing a `SecureField` to retype a password of the same length
(bullets either way). Only the text-entry elements are compared — not the whole
tree, which the status-bar clock changes every second.

Emptying a field (`"clear": true` with `"text": ""`) is the exception: there the
clear IS the effect, so the comparison brackets the clear instead and the step
fails only when the field kept its value.

The step distinguishes three failures, because the right response differs:

| Message | Meaning | Safe to retry? |
|---|---|---|
| `text entry not attempted` | No field on screen, or the tree could not be read at all — checked BEFORE anything is typed | Yes, nothing was sent |
| `text entry had no effect` | The field's content did not change; the keystrokes did not land | Yes, but expect the same result until the cause is fixed |
| `could not verify text entry` | The tree could not be read back afterward | **No** — the text WAS sent, so a blind retry can enter it twice |

Measured limits of the keyboard paths, all on Xcode 27.0 beta 4:

- **A worn-out simulator delivers NONE of it**: paste, `keyboard`, and `clear`
  all leave the field untouched. Measured 2026-08-01: this follows DEVICE age,
  not the iOS version — a freshly created device types fine on iOS 27.0, while
  long-lived devices fail on both iOS 27.0 and 26.4, and neither `simctl erase`
  nor a reboot revives them. `simctl create` a replacement to confirm. The
  `verify-effect` check turns the silent no-op into an explicit step failure that
  names `set-text` as the fix.
- Under a **non-Latin IME** (a Japanese keyboard, for example) `"input-method":
  "keyboard"` text arrives as an in-progress COMPOSITION, not committed text:
  `abc` shows up as `あbc`, and dismissing the composition discards all of it.
  `describe-ui` reports composing text in AXValue, so a `verify` can pass on text
  the field never committed.
- `"clear": true` is unreliable while a composition is pending: the select-all is
  swallowed by the IME and only one character is deleted, so old text survives
  (`あbc` + clear + `world` measured as `あb world`). With no composition pending
  it clears exactly.

`set-text` has none of these failure modes — prefer it whenever the step only
needs the field to hold a given value.

`set-text` — write a field's content WITHOUT typing (targets the element like `tap`:
exactly one of `selector` / `point`, plus `text`):

```json
{ "type": "set-text", "selector": { "id": "login.email" }, "text": "user@example.com" }
```

`set-text` sets the element's accessibility value directly, so it needs no keyboard,
no pasteboard, and no focus, and it carries any text (Japanese, emoji) regardless of
the guest keyboard layout or IME. It is the only text-entry action that works on a
device that has stopped delivering keyboard HID, where `type`
silently enters nothing. The write is confirmed against a fresh read of the app, so
the step FAILS when the value did not take — only editable text elements accept it.

Because nothing is typed, per-keystroke behaviour is not exercised (`onChange` per
character, keyboard toolbars, autocomplete, IME composition) — and a field that
filters input as it is typed (a length cap, a character whitelist) may accept a
value through this path that a user could not have typed (not measured; assume it
can happen). Choose per intent: `set-text` when the field's content is what
matters, `type` when the typing itself is under test.

Three constraints to plan around:

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

- Clearing a field with `"text": ""` cannot be confirmed: an empty field reports its
  PLACEHOLDER as AXValue, which never equals `""`. Pair an empty write with
  `"verify-value": false` and assert on the app's own output.

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

`double-tap` (selector or `point`, same targeting as `tap`) — zoom-to-fit in map
and photo views, double-tap-to-select text. Two full taps inside the system
double-tap window, which two separate `tap` steps cannot guarantee:

```json
{ "type": "double-tap", "selector": { "label": "Map" } }
```

`pinch` (`direction` is `in` (zoom out) or `out` (zoom in)). Optional `point` is
the gesture center (default: screen center), `separation` is the widest
normalized finger gap (default 0.4, must be above 0.05 and at most 1.0), `steps`
is the interpolated move count (default 20, max 200), `duration` is the total
seconds (default 0.5, must be above 0 and at most 30 — the same bound as
`sipi pinch`, because 0 collapses the gesture into a single instant frame that no
recognizer reads as a pinch). The two contacts travel along the vertical axis through
the center, and a center near an edge shortens the travel rather than moving a
contact off screen — a center so close to an edge that no travel is left is a
step failure, not a silent no-op:

```json
{ "type": "pinch", "direction": "out", "point": { "x": 0.5, "y": 0.4 }, "separation": 0.6 }
```

`multitouch` (raw two-finger phase — `points` is exactly two points, `phase` is 1
(begin/move) or 2 (end)). Use `pinch` unless the gesture is not a pinch;
this is the escape hatch for hand-assembled two-finger sequences such as a
rotate:

```json
{ "type": "multitouch", "phase": 1, "points": [{ "x": 0.4, "y": 0.4 }, { "x": 0.6, "y": 0.6 }] }
{ "type": "multitouch", "phase": 2, "points": [{ "x": 0.3, "y": 0.3 }, { "x": 0.7, "y": 0.7 }] }
```

All keycodes are USB HID usage codes 0…255. `long-press`/`double-tap`/`slider` selectors honor the same fast→deep resolution and `optional` skip as `tap`.

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

### Device-state actions (Xcode 27+)

These reach facets simctl never exposed. They go through `xcrun devicectl`, which
only speaks to simulators from Xcode 27 on; on an older toolchain the step fails
with an explicit message rather than a device-not-found error. Every facet these
touch is captured once per run and restored afterward, like `appearance` and
Dynamic Type. The capture happens before the first write and a step FAILS when it
cannot be read — changing the device with no way to change it back is worse than
not running the step. The same applies per facet: if the runtime does not report
one the action wants to change, the step fails rather than leaving it applied for
the rest of the run.

One facet cannot be restored and so is refused outright rather than silently
left behind: `look-and-feel` on a runtime that offers a single look (iOS 27 has
only "Liquid Glass"), where devicectl accepts the write and ignores it.

Drive a Face ID / Touch ID flow end to end. Enrollment must be on before a match
event has a prompt to answer, so the order is enroll → present the prompt →
match:

```json
{ "type": "biometrics", "operation": "enroll" }
{ "type": "biometrics", "operation": "match" }
{ "type": "biometrics", "operation": "no-match" }
{ "type": "biometrics", "operation": "unenroll" }
```

Set the accessibility appearance facets simctl cannot reach. Every key is
optional; at least one is required, and an unknown key is a validation error
rather than a silently ignored setting:

```json
{
  "type": "display-state",
  "settings": {
    "reduce-motion": true,
    "reduce-transparency": true,
    "show-borders": true,
    "color-filter": true,
    "color-filter-type": "deuteranopia",
    "color-filter-intensity": 0.8,
    "liquid-glass-opacity": 1.0,
    "larger-accessibility-sizes": true,
    "look-and-feel": "tinted"
  }
}
```

| Facet | Values |
|---|---|
| `look-and-feel` | `clear`, `tinted` |
| `reduce-motion`, `reduce-transparency`, `show-borders`, `color-filter`, `larger-accessibility-sizes` | boolean |
| `color-filter-type` | `grayscale`, `protanopia`, `deuteranopia`, `tritanopia` |
| `color-filter-intensity` | 0.25…1.0. Cannot be combined with `grayscale`, which takes no intensity — `sipi validate` rejects the pair, because devicectl refuses the write and leaves the whole batch unapplied |

`color-filter-type` and `color-filter-intensity` require `color-filter` in the
same settings object. devicectl only reports those two while the filter is ON, so
a run that starts with it off has no baseline to restore them from; switching the
filter back off is what returns the screen to its original appearance.
| `liquid-glass-opacity` | 0.0 (translucent) … 1.0 (opaque) |

Light/dark, text size, and Increase Contrast are NOT settable here even though
devicectl can write them: the `appearance`, `content-size`, and
`increase-contrast` actions already own those facets and capture their own
restore baselines. Two mechanisms moving one facet would mean two baselines and a
restore that lands on whichever ran last, so `sipi validate` rejects them here
and names the action to use instead.

Turn VoiceOver on for an accessibility pass and off afterward:

```json
{ "type": "voiceover", "enabled": true }
```

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

A step passes when EVERY condition across every form holds. At least one
condition is required — an empty verify would pass without checking anything and
is rejected by `sipi validate`.

### Text forms

```json
{
  "contains": ["Settings"],
  "absent": ["Home only text"],
  "matches": ["Total: \\d+ items"],
  "not-matches": ["Error \\d+"]
}
```

- `contains`: every string must appear in `describe-ui`.
- `absent`: every string must be absent from `describe-ui`.
- `matches`: every regular expression must match somewhere in `describe-ui`.
- `not-matches`: no regular expression may match.
- Patterns are search semantics, like grep; anchor with `^` / `$` when you mean
  the whole string. An uncompilable pattern is a validation error, not a run-time
  surprise.
- Use strings that prove the new state, not static chrome.

### Element form

`elements` asserts about ELEMENTS rather than about the serialized text, which is
what makes a check like "the button is disabled" or "there are exactly five rows"
expressible at all:

```json
{
  "elements": [
    { "label": "Sign In", "enabled": false },
    { "element-type": "Cell", "count": 5 },
    { "id": "login.email", "value-matches": "@example\\.com$" },
    { "label": "Close", "min-width": 44, "min-height": 44 },
    { "label": "Error banner", "exists": false }
  ]
}
```

Selector fields (at least one required; they are ANDed):

| Field | Type | Description |
|---|---|---|
| `id` | string | Exact `AXUniqueId` |
| `label` | string | Exact `AXLabel` |
| `value` | string | Exact `AXValue` |
| `element-type` | string | Accessibility type such as `Button` or `Cell` |

Assertion fields (all optional; a bare selector means "must exist"):

| Field | Type | Description |
|---|---|---|
| `exists` | bool | Whether any element must match (default true) |
| `enabled` | bool | Required enabled state for every match |
| `value-equals` | string | Required exact `AXValue` for every match |
| `value-matches` | string | Regular expression that must match somewhere in every match's `AXValue` (search semantics, like `matches`; anchor with `^` / `$` for a whole-value match) |
| `count` | int | Exact number of matches |
| `min-count` / `max-count` | int | Bounds on the number of matches |
| `min-width` / `min-height` | number | Minimum frame extent in points for every match — the assertion form of the 44pt touch-target rule |

String comparisons are exact after trimming; use `contains` for substring
matching. Asserting a property of an element that does not exist FAILS ("no
element matched") rather than passing over an empty set, so an element condition
can never green a step vacuously.

`sipi validate` rejects a condition with no selector, contradictory counts
(`min-count` above `max-count`, `count` alongside `min-count`/`max-count`), and
`exists: false` paired with a property assertion.

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
