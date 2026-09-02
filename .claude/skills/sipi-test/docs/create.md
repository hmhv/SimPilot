# Test Creation

Produce explicit v2 JSON that `sipi run-test` executes without model
interpretation.

## Workflow

1. Understand the user goal and the affected screen.
2. Observe the real UI with `sipi describe-ui "$UDID"` and screenshots
   (`--format compact` to scan a screen for selectors; the JSON form when a
   verify string has to be copied exactly).
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

## Seed data with fixtures

Use top-level `fixtures` when a repeatable test needs a file in the app data
container, an App Group, or experimental Files.app storage. Do not add an app
debug hook or copy into CoreSimulator paths by hand.

```json
{
  "id": "import-account",
  "title": "Import an account fixture",
  "fixtures": [
    {
      "source": "fixtures/account.json",
      "destination": "Documents/Inbox/account.json"
    }
  ],
  "steps": [
    {
      "verify": { "contains": ["Account imported"] }
    }
  ]
}
```

Keep fixture sources beneath `.simpilot`; both source and destination are safe
relative paths. Set `group-id` for an App Group, or `files-app: true` and
optionally `storage` for a candidate returned by `sipi files-app candidates`.
Do not combine those target modes. The harness terminates the app, installs the
fixtures before launch, and restores the original files afterward. A test with
fixtures cannot use `--no-launch`. A Files.app fixture can only be verified
through the app's UI flow; `verify.container-files` cannot read File Provider
Storage.

## Choosing an action

The full type list is the table in `../references/json-reference.md`; each shape
and its constraints are in `../references/actions.md`. Two choices come up often
enough to state here:

- **Text entry**: `set-text` by default — it needs no focus, keyboard, or
  pasteboard and works on a simulator that has stopped accepting keyboard HID.
  Use `type` only when the keystrokes themselves are under test; on such a
  device it falls back to Xcode 27's service when that is set up, and fails
  loudly otherwise.
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
- `verify.container-files` asserts what the app persisted, independently or
  alongside UI checks. Use `exists`, `size`, or `sha256` for metadata; use
  `equals` with `text`, `json`, `plist`, or read-only `sqlite`. JSON/plist may
  select `key-path`; SQLite requires `query`. Set `group-id` to inspect shared
  App Group state. It does not support Files.app storage. See
  `../references/json-reference.md` for the exact schema.
- A normal step's `verify` block cannot judge layout, color, or whether
  something *looks* right; route a one-off visual judgment to `sipi-verify`.
  The appearance, accessibility, and localization audit modes in this skill
  still inspect screenshots under their dedicated workflows. Keep non-visual
  file-state checks in `verify.container-files`, even though they do not come
  from `describe-ui`. Disabled state, element counts, exact values, and
  touch-target size are also mechanical: express them with `verify.elements`
  rather than deferring them.
