# Test Creation

Create SimPilot v2 specs: explicit JSON that `sipi run-test` can execute without model interpretation.

## Workflow

1. Understand the user goal and affected screen.
2. Use `sipi describe-ui <udid>` and screenshots to observe the real UI.
3. Prefer stable `AXUniqueId` values. Use labels only when unique and stable.
4. Write `.simpilot/tests/<id>.json` using the v2 schema in `../references/json-reference.md`.
5. Run `sipi validate .simpilot`.
6. If asked to create and run, execute `sipi run-test .simpilot/tests/<id>.json --workspace .simpilot`.

## v2 Step Shape

Use explicit action and verify objects:

```json
{
  "id": "settings-toggle",
  "title": "Settings Toggle",
  "steps": [
    {
      "id": "open-settings",
      "action": {
        "type": "tap",
        "selector": { "id": "tab.settings" }
      },
      "verify": {
        "contains": ["Settings"],
        "absent": ["Home only text"]
      },
      "wait": 3
    }
  ]
}
```

Here the step-level `"wait": 3` is the **verify poll timeout** — how long the harness re-polls `describe-ui` for the `verify` rows before failing the step (default 3s). It only matters for steps that have a `verify` block; it is not a pre-action sleep. To insert a deliberate pause, use a `wait` *action* (`{ "type": "wait", "duration": 1.0 }`).

Do not write natural-language actions such as `"Tap Settings"`. The harness does not interpret prose.

## Action Types

- `tap`: requires `selector` or `point`
- `double-tap`: same targeting as `tap` — zoom-to-fit in map/photo views, double-tap-to-select text. Two taps inside the system double-tap window, which two `tap` steps cannot guarantee
- `long-press`: `selector` or `point`; optional `duration` hold (default 0.5s) — context menus, reorder handles
- `set-text`: **the default for putting content in a field.** Requires `text` and exactly one of `selector` / `point`; writes the element's accessibility value instead of typing, so it needs no focus, no keyboard, and no pasteboard, takes any script, and is the only text action that still works on a simulator whose keyboard HID has stopped being delivered. The target must be on screen (it is hit-tested like a tap); a field that reports masked/reformatted text — a `SecureField` reads back as bullets — needs `"verify-value": false` (the saved-test counterpart of the CLI's `sipi set-text --no-verify`), as does clearing with `"text": ""` (an empty field reports its placeholder). Nothing is typed, so per-keystroke behaviour is not exercised and an input filter may be bypassed
- `type`: keystroke-level entry — use it only when the TYPING is the subject (per-character `onChange`, keyboard toolbar, candidate bar, Return/submit); otherwise use `set-text`. Requires `text` and an already-focused field. Pastes via the pasteboard by default; `"input-method": "keyboard"` injects US-only keystrokes; `"clear": true` selects all and deletes first. The step FAILS when the field's content did not change, so a runtime that drops keystrokes cannot produce a green step over an empty field; `"verify-effect": false` opts out for a field whose insertion is genuinely invisible. Measured limits: a worn-out simulator delivers nothing at all (surfaced as a step failure; it follows device age, not the iOS version — see `../../sipi-common/docs/troubleshooting.md`), and under a non-Latin IME keyboard text stays an uncommitted composition (so a `verify` can pass on text the field never committed) while `"clear": true` then deletes only one character
- `key`: requires USB HID `usage`
- `key-combo`: requires `modifiers` (keycodes) and `key` — e.g. Cmd+A is `{ "modifiers": [227], "key": 4 }`
- `key-sequence`: requires `keycodes`; optional `delay` between presses
- `button`: requires `button` (`home`, `lock`, `side_button`, `app_switcher`, `siri`, `swipe_home`)
- `swipe`: requires `start` and `end` points
- `drag`: requires `start` and `end`; optional `steps` (1…1000) and `duration` — interpolated, smoother than `swipe`
- `gesture`: requires `preset` (`scroll-*` / `swipe-from-*-edge`); optional `duration`
- `pinch`: requires `direction` (`in` = zoom out, `out` = zoom in); optional `point` (gesture center), `separation` (widest normalized gap, default 0.4), `steps` (default 20, max 200), `duration`
- `multitouch`: raw two-finger phase — requires exactly two `points` and a `phase` (1 = begin/move, 2 = end). Use `pinch` unless the gesture is not a pinch (a rotation, say)
- `slider`: requires `selector` (id/label) and `value` (0…100); optional `tolerance`. Drags then verifies AXValue
- `orientation`: requires `orientation` (`portrait`/`landscape-left`/…). Use to test rotation
- `crown`: requires `delta` (Apple Watch only)
- `wait`: a sleep action; optional `duration` (default 1s). Distinct from the step-level `wait` field, which is the verify poll timeout in seconds (default 3s), not a sleep
- Simulator controls: `privacy`, `open-url`, `push`, `location`, `appearance`, `content-size`, `increase-contrast`, `status-bar`, `launch`, `terminate`, and provider-backed `network-condition`
- Device state via devicectl (Xcode 27+): `biometrics` (`enroll` / `unenroll` / `match` / `no-match` — enroll before a match has a prompt to answer), `display-state` (`settings` object: reduce motion, reduce transparency, show borders, color filter + type/intensity, Liquid Glass opacity, Larger Accessibility Sizes, look and feel), `voiceover` (`enabled`). Light/dark, text size, and Increase Contrast belong to the `appearance` / `content-size` / `increase-contrast` actions and are rejected inside `display-state`. Each captures its restore baseline before the first write and FAILS the step when it cannot read it — changing the device with no way to change it back is worse than skipping the step

These let you test toggles/sliders/menus/gestures deterministically (e.g. `slider` instead of a fragile coordinate drag). See `../references/json-reference.md` for full JSON shapes.

For network failures, permission denial, deep links, pushes, location, or other externally controlled error states, read `../references/adverse-state-testing.md` before writing the spec.

## Selectors and Points

Selector:

```json
{ "id": "auth.sign-in" }
{ "label": "Sign In" }
{ "value": "42" }
```

Point:

```json
{ "x": 0.5, "y": 0.8, "unit": "norm" }
{ "x": 200, "y": 700, "unit": "pixel" }
```

Use coordinates only when no stable accessibility target exists.

## Verify Rules

- `verify.contains` strings must represent the new state created by the action.
- `verify.absent` strings are negative controls.
- Avoid static chrome and labels that appear on both success and failure paths.
- `verify.matches` / `verify.not-matches` take regular expressions over the same tree text — use them for text that varies (a count, a timestamp, an ID) where an exact string would be brittle. Search semantics, like grep; anchor with `^` / `$`.
- `verify.elements` asserts about elements rather than text: `{"label": "Submit", "enabled": false}`, `{"element-type": "Cell", "count": 5}`, `{"id": "email", "value-matches": "@example\\.com$"}`, `{"label": "Close", "min-width": 44, "min-height": 44}`, `{"label": "Error", "exists": false}`. Prefer it whenever the property — not the presence of a string — is what the step proves.
- If a check cannot be made mechanically with `describe-ui` (a visual judgment: layout, color, whether something *looks* right), use `sipi-verify` instead of `sipi-test`. Disabled state, element counts, exact values, and touch-target size are all mechanical — express them with `verify.elements` rather than deferring them.
