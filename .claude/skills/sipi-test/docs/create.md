# Test Creation

Produce explicit v2 JSON that `sipi run-test` executes without model
interpretation.

## Workflow

1. Understand the user goal and the affected screen.
2. Observe the real UI with `sipi describe-ui "$UDID"` and screenshots.
3. Prefer stable `AXUniqueId` values. Use labels only when unique and stable.
4. Write `.simpilot/tests/<id>.json` against `../references/json-reference.md`.
5. `sipi validate .simpilot` and fix schema issues before running.
6. If asked to create *and* run:
   `sipi run-test .simpilot/tests/<id>.json --workspace .simpilot`.

## Step shape

```json
{
  "id": "settings-toggle",
  "title": "Settings Toggle",
  "steps": [
    {
      "id": "open-settings",
      "action": { "type": "tap", "selector": { "id": "tab.settings" } },
      "verify": { "contains": ["Settings"], "absent": ["Home only text"] },
      "wait": 3
    }
  ]
}
```

Natural-language actions such as `"Tap Settings"` are not valid — the harness
does not interpret prose.

The step-level `"wait"` is the **verify poll timeout**, not a pre-action sleep.
For a deliberate pause, use a `wait` action.

## Choosing an action

The full type list is the table in `../references/json-reference.md`; each shape
and its constraints are in `../references/actions.md`. Two choices come up often
enough to state here:

- **Text entry**: `set-text` by default — it needs no focus, keyboard, or
  pasteboard and works on a simulator whose keyboard HID has stopped being
  delivered. Use `type` only when the keystrokes themselves are under test.
- **Deterministic controls over coordinates**: `slider`, `double-tap`,
  `long-press`, `gesture`, `drag`, and `pinch` exist so a toggle, menu, or
  gesture does not have to be a fragile coordinate drag.

For network failures, permission denial, deep links, pushes, location, or any
other externally controlled error state, read
`../references/adverse-state-testing.md` before writing the spec.

## Selectors and points

```json
{ "id": "auth.sign-in" }
{ "label": "Sign In" }
{ "value": "42" }

{ "x": 0.5, "y": 0.8, "unit": "norm" }
{ "x": 200, "y": 700, "unit": "pixel" }
```

Use coordinates only when no stable accessibility target exists.

## Verify rules

- `verify.contains` must represent the NEW state the action created.
- `verify.absent` strings are the negative controls.
- Avoid static chrome and labels that appear on both the success and failure
  paths.
- `verify.matches` / `not-matches` take regular expressions over the same tree
  text — use them for values that vary (a count, a timestamp, an ID) where an
  exact string would be brittle.
- `verify.elements` asserts about elements rather than text —
  `{"label": "Submit", "enabled": false}`, `{"element-type": "Cell", "count": 5}`,
  `{"label": "Close", "min-width": 44, "min-height": 44}`. Prefer it whenever the
  property, not the presence of a string, is what the step proves.
- If a check cannot be made mechanically from `describe-ui` — layout, color,
  whether something *looks* right — it belongs in `sipi-verify`, not here.
  Disabled state, element counts, exact values, and touch-target size are all
  mechanical: express them with `verify.elements` rather than deferring them.
