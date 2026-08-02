# Action Reference

Every v2 action type, with its JSON shape and the constraints `sipi validate`
enforces. The file/step/verify schema is in `json-reference.md`; the CLI
equivalents are in `../../sipi-common/docs/ui-driver.md`.

All keycodes are USB HID usage codes 0…255.

`tap`, `double-tap`, `long-press`, and `set-text` share one targeting model:
exactly one of `selector` or `point`, resolved fast tree → deep tree.

`slider` is the exception: it **requires** a `selector`, and that selector must
use `id` or `label`. A slider is planned from the resolved element's frame, so
`point` is never read for this action — `sipi validate` rejects it whether it
appears alone or alongside a valid selector, and rejects a selector that uses
`value`.

### `optional` is narrower and blunter than it looks

The harness pre-resolves the target only for `tap`, `double-tap`, `long-press`,
and `slider`. Every other action is **deliberately excluded from that
pre-resolution** and runs regardless — including `set-text`, which does take a
`selector` / `point` but is not on the list. An `optional` `set-text` against a
missing field is executed anyway and FAILS.

A step skips only when the target is genuinely **not found in both the fast and
the deep tree**. Anything else the lookup runs into — an ambiguous selector
matching several elements, an accessibility tree that could not be read, a
malformed selector — does **not** skip: the pre-resolution gives up and the step
proceeds to normal execution, which then decides. A transient tree read failure
can therefore still pass on the step's own retry, while a genuinely ambiguous
selector fails there with its real error.

A **degenerate tree** — the single empty root the bridge answers with until the
app is reachable, common right after a launch — is explicitly not "absent". The
pre-resolution waits it out, and if the tree never becomes usable it declines to
decide rather than skip. Otherwise an optional step could go green for an element
that had simply not come up yet.

Either way, a skip is evidence the element was absent, not a catch-all for "the
lookup did not work out".

**`optional` does not gate the steps after it.** A skipped step still reports
`passed: true`, so the run continues normally and the next step executes
regardless. There is no conditional-branch mechanism in a v2 spec: a `set-text`
following an `optional` `tap` runs even when that tap was skipped, and fails if
the field is not there. Model a genuinely conditional flow as a separate test
with its own preconditions, not as optional steps inside one.

## Input

`tap`:

```json
{ "type": "tap", "selector": { "id": "tab.settings" } }
{ "type": "tap", "point": { "x": 0.5, "y": 0.8, "unit": "norm" } }
```

`double-tap` — zoom-to-fit in map and photo views, double-tap-to-select text. Two
full taps inside the system double-tap window, which two separate `tap` steps
cannot guarantee:

```json
{ "type": "double-tap", "selector": { "label": "Map" } }
```

`long-press` — context menus, reorder handles. `duration` is the hold in seconds
(default 0.5):

```json
{ "type": "long-press", "selector": { "label": "Photo" }, "duration": 0.6 }
```

`key`, `key-combo` (hold `modifiers`, press `key`, release LIFO — Cmd+A is
227,4), `key-sequence` (press+release each in order; `delay` default 0.1s):

```json
{ "type": "key", "usage": 40 }
{ "type": "key-combo", "modifiers": [227], "key": 4 }
{ "type": "key-sequence", "keycodes": [11, 8, 15, 15, 18], "delay": 0.1 }
```

`button` — `home`, `lock`, `side_button`, `app_switcher`, `siri`, `swipe_home`:

```json
{ "type": "button", "button": "home" }
```

`wait` — a sleep. Distinct from the step-level `wait` field, which is the verify
poll timeout:

```json
{ "type": "wait", "duration": 1.0 }
```

## Text entry

**`set-text` is the default.** It writes the element's accessibility value
directly, so it needs no keyboard, no pasteboard, and no focus, and it carries any
text (Japanese, emoji) regardless of the guest keyboard layout or IME. It is the
only text action that works on a device that has stopped delivering keyboard HID.
The write is confirmed against a fresh read of the app, so the step FAILS when the
value did not take — only editable text elements accept it.

```json
{ "type": "set-text", "selector": { "id": "login.email" }, "text": "user@example.com" }
```

Three constraints to plan around:

- **The target must be on screen.** The write goes through a hit-test at the
  element's activation point, so a field scrolled out of view (or hidden behind
  the keyboard) has a frame but cannot be hit. Scroll it into view first, exactly
  as before a `tap`.
- **A field that reports something other than what was written** fails the
  built-in confirmation. `SecureField` is the common case: the write lands
  (measured — an 11-character write reached the app) but AXValue reads back as
  `•••••••••••`. Use `"verify-value": false` and assert on the app's own output.
- **Clearing with `"text": ""` cannot be confirmed**: an empty field reports its
  PLACEHOLDER as AXValue, which never equals `""`. Same treatment.

```json
{ "type": "set-text", "selector": { "id": "login.password" }, "text": "s3cret", "verify-value": false }
```

`"verify-value": false` records the method as `set-text…+unverified` in
`result.json`, so the artifact never implies a confirmation that did not happen.
It is the saved-test counterpart of `sipi set-text --no-verify`.

Because nothing is typed, per-keystroke behavior is not exercised (`onChange` per
character, keyboard toolbars, autocomplete, IME composition), and a field that
filters input as it is typed — a length cap, a character whitelist — may accept a
value a user could not have typed (not measured; assume it can happen).

**`type` is for steps where the TYPING is the subject** — per-character
`onChange`, keyboard toolbar, candidate bar, Return/submit. The field must
already be focused (tap it first):

```json
{ "type": "type", "text": "hello@example.com" }
{ "type": "type", "text": "1234", "input-method": "keyboard" }
{ "type": "type", "text": "replaced", "clear": true }
```

By default `type` pastes through the simulator pasteboard (Cmd+V), independent of
the guest keyboard layout and input language. `"input-method": "keyboard"` sends
real per-character keystrokes but supports US-keyboard characters only and is
rejected for accented / non-Latin / emoji text. Pasting clobbers and best-effort
restores the simulator pasteboard, which is synced with the Mac pasteboard — the
host clipboard is transiently replaced too.

Both methods insert at the caret, so a field that already holds text ends up with
both strings. `"clear": true` selects all (Cmd+A) and deletes first.

`type` confirms it did something: it compares the text fields' contents before and
after insertion and FAILS when nothing changed, so a simulator that has stopped
delivering keyboard events cannot produce a green step over an empty field. Set
`"verify-effect": false` for the rare field whose insertion is genuinely invisible.

The comparison is against the field as it stands AFTER any `clear`, so the two
idioms that end where they started still pass: `"clear": true` with the same
string, and clearing a `SecureField` to retype a password of the same length
(bullets either way). Only text-entry elements are compared — not the whole tree,
whose status-bar clock changes every second. Emptying a field (`"clear": true`
with `"text": ""`) is the exception: there the clear IS the effect, so the
comparison brackets the clear and the step fails only if the field kept its value.

`type`'s three distinct failure messages, what each means, whether a retry is
safe, and the measured limits (worn-out simulator, non-Latin IME composition,
`clear` against a pending composition) are in
`../../sipi-common/docs/troubleshooting.md` § `type` failures. `set-text` has none
of those failure modes.

## Gestures

`swipe`:

```json
{
  "type": "swipe",
  "start": { "x": 0.5, "y": 0.8, "unit": "norm" },
  "end": { "x": 0.5, "y": 0.2, "unit": "norm" },
  "duration": 0.3
}
```

`drag` — interpolated point-to-point, smoother and more reliable than `swipe`
(`steps` 1…1000, default 60; `duration` default 0.6). `sipi validate` enforces
the `steps` range, so a spec can never ask for a count the harness would quietly
clamp to something else:

```json
{ "type": "drag", "start": { "x": 0.5, "y": 0.7 }, "end": { "x": 0.5, "y": 0.3 }, "steps": 60 }
```

`gesture` — `preset` is one of `scroll-{up,down,left,right}` or
`swipe-from-{left,right,top,bottom}-edge`; optional `duration`:

```json
{ "type": "gesture", "preset": "scroll-down" }
```

`pinch` — `direction` is `in` (zoom out) or `out` (zoom in). Optional `point` is
the gesture center (default: screen center), `separation` the widest normalized
finger gap (default 0.4; above 0.05, at most 1.0), `steps` the interpolated move
count (default 20, max 200), `duration` the total seconds (default 0.5; above 0,
at most 30 — 0 collapses the gesture into one instant frame that no recognizer
reads as a pinch). The contacts travel along the vertical axis through the
center; a center near an edge shortens the travel rather than moving a contact
off screen, and a center so close that no travel is left is a step failure, not a
silent no-op:

```json
{ "type": "pinch", "direction": "out", "point": { "x": 0.5, "y": 0.4 }, "separation": 0.6 }
```

`multitouch` — the escape hatch for a two-finger gesture that is not a pinch, such
as a rotation. `points` is exactly two, `phase` is 1 (begin/move) or 2 (end):

```json
{ "type": "multitouch", "phase": 1, "points": [{ "x": 0.4, "y": 0.4 }, { "x": 0.6, "y": 0.6 }] }
{ "type": "multitouch", "phase": 2, "points": [{ "x": 0.3, "y": 0.3 }, { "x": 0.7, "y": 0.7 }] }
```

`slider` — `selector` (id or label) plus `value` 0…100; optional `tolerance`
(normalized 0…1, default 0.02). Resolves the slider, drags the thumb, then polls
AXValue; the step fails if it cannot reach the target:

```json
{ "type": "slider", "selector": { "label": "Volume", "element-type": "Slider" }, "value": 75 }
```

`orientation` (`portrait` | `portrait-upside-down` | `landscape-left` |
`landscape-right` | `face-up` | `face-down`) and `crown` (Digital Crown delta,
Apple Watch simulators only):

```json
{ "type": "orientation", "orientation": "landscape-left" }
{ "type": "crown", "delta": 40 }
```

## Simulator controls

Read `adverse-state-testing.md` before writing a spec that depends on one of
these — it covers provider capability checks, cleanup, and what each control does
and does not actually change.

```json
{ "type": "open-url", "url": "myapp://settings" }
{ "type": "privacy", "operation": "revoke", "service": "photos" }
{ "type": "push", "payload": { "aps": { "alert": "New message" } } }
{ "type": "location", "operation": "set", "latitude": 35.6812, "longitude": 139.7671 }
{ "type": "location", "operation": "clear" }
{ "type": "appearance", "appearance": "dark" }
{ "type": "content-size", "content-size": "accessibility-large" }
{ "type": "increase-contrast", "enabled": true }
{ "type": "status-bar", "operation": "override", "arguments": ["--time", "9:41", "--batteryLevel", "100"] }
{ "type": "status-bar", "operation": "clear" }
{ "type": "launch", "arguments": ["--fixture"], "environment": { "API_MODE": "fixture" } }
{ "type": "terminate" }
{ "type": "network-condition", "operation": "apply", "profile": "packet-loss-100" }
{ "type": "network-condition", "operation": "clear" }
```

- `privacy` `operation` is `grant`, `revoke`, or `reset`. Harness privacy actions
  are always app-scoped, including `reset all`.
- `push` payloads must contain an `aps` object and encode to at most 4096 bytes.
- `status-bar` `arguments` are passed straight to `simctl status_bar … override`.
  They change screenshot chrome only — not connectivity, battery, or radio state.
- `launch` environment keys omit the `SIMCTL_CHILD_` prefix; SimPilot adds it.
- `network-condition` requires an explicitly configured external provider.
- `bundle-id` optionally overrides the configured app for `privacy`, `push`,
  `launch`, `terminate`, and `network-condition`.

## Device state (Xcode 27+)

These reach facets simctl never exposed, through `xcrun devicectl`, which only
speaks to simulators from Xcode 27 on. On an older toolchain the step fails with
an explicit message rather than a device-not-found error (see
`../../sipi-common/docs/troubleshooting.md`).

Every facet **the runtime reports** is captured once per run and restored
afterward. The capture happens before the first write, and a step FAILS when the
baseline cannot be read — changing the device with no way to change it back is
worse than not running the step. The same applies per facet: if the runtime does
not report one the action wants to change, the step fails rather than leaving it
applied for the rest of the run. One facet is refused outright because it cannot
be restored: `look-and-feel` on a runtime that offers a single look (iOS 27 has
only "Liquid Glass"), where devicectl accepts the write and ignores it.

**The color-filter pair is the one facet with a residue.** devicectl reports
`color-filter-type` and `color-filter-intensity` only while the filter is ON, so
a run that starts with the filter OFF restores neither — the restore switches the
filter off, which is visually correct, but the kind and intensity the step set
stay in the device's stored settings.

When the baseline filter is already ON, each facet the step changes is checked on
its own, and the step is **refused before it writes** if that facet could not be
put back: no reported baseline value, an intensity outside 0.25…1.0, or an
intensity change against a `grayscale` baseline (devicectl will not take the two
together). Facets the step does not change are never consulted, and a step that
leaves the pair alone is never refused. `adverse-state-testing.md` has the table
and the measure that covers every case — a disposable simulator.

`biometrics` — enrollment must be on before a match event has a prompt to answer,
so the order is enroll → present the prompt → match:

```json
{ "type": "biometrics", "operation": "enroll" }
{ "type": "biometrics", "operation": "match" }
{ "type": "biometrics", "operation": "no-match" }
{ "type": "biometrics", "operation": "unenroll" }
```

`display-state` — every key is optional, at least one is required, and an unknown
key is a validation error rather than a silently ignored setting:

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
| `reduce-motion`, `reduce-transparency`, `show-borders`, `color-filter`, `larger-accessibility-sizes` | boolean |
| `look-and-feel` | `clear`, `tinted` |
| `color-filter-type` | `grayscale`, `protanopia`, `deuteranopia`, `tritanopia` |
| `color-filter-intensity` | 0.25…1.0. Rejected with `grayscale`, which takes no intensity — devicectl refuses the write and leaves the whole batch unapplied |
| `liquid-glass-opacity` | 0.0 (translucent) … 1.0 (opaque) |

`color-filter-type` and `color-filter-intensity` require `color-filter` in the
same settings object. devicectl reports those two only while the filter is ON, so
a run that starts with it off has no baseline to restore them from; switching the
filter back off is what returns the screen to its original appearance.

Light/dark, text size, and Increase Contrast are NOT settable here even though
devicectl can write them: the `appearance`, `content-size`, and
`increase-contrast` actions own those facets and capture their own restore
baselines. Two mechanisms moving one facet would mean two baselines and a restore
that lands on whichever ran last, so `sipi validate` rejects them here and names
the action to use instead.

`voiceover`:

```json
{ "type": "voiceover", "enabled": true }
```
