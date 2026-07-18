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
- `long-press`: `selector` or `point`; optional `duration` hold (default 0.5s) — context menus, reorder handles
- `type`: requires `text`; the focused field must already be active
- `key`: requires USB HID `usage`
- `key-combo`: requires `modifiers` (keycodes) and `key` — e.g. Cmd+A is `{ "modifiers": [227], "key": 4 }`
- `key-sequence`: requires `keycodes`; optional `delay` between presses
- `button`: requires `button` (`home`, `lock`, `side_button`, `app_switcher`, `siri`, `swipe_home`)
- `swipe`: requires `start` and `end` points
- `drag`: requires `start` and `end`; optional `steps` (1…1000) and `duration` — interpolated, smoother than `swipe`
- `gesture`: requires `preset` (`scroll-*` / `swipe-from-*-edge`); optional `duration`
- `slider`: requires `selector` (id/label) and `value` (0…100); optional `tolerance`. Drags then verifies AXValue
- `orientation`: requires `orientation` (`portrait`/`landscape-left`/…). Use to test rotation
- `crown`: requires `delta` (Apple Watch only)
- `wait`: a sleep action; optional `duration` (default 1s). Distinct from the step-level `wait` field, which is the verify poll timeout in seconds (default 3s), not a sleep

These let you test toggles/sliders/menus/gestures deterministically (e.g. `slider` instead of a fragile coordinate drag). See `../references/json-reference.md` for full JSON shapes.

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
- If a check cannot be made mechanically with `describe-ui`, use `sipi-verify` instead of `sipi-test`.
