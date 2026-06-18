# Test Creation

## Steps

1. **Understand requirements**: Clarify the test target, purpose, and expected behavior. Ask if anything is unclear
2. **Design the test**:
   - Build & install (if `build` is in config.json; see docs/run.md for details)
   - Confirm screens in Simulator: `ui_screenshot` + `Read` + `ui_describe`
   - Reference source code: use `Glob`/`Grep` to understand navigation structure and display conditions
3. **Generate JSON and present to user** → save to `.simpilot/tests/<id>.json` after confirmation
4. **Suggest "Would you like to run it now?"**

When asked to "create and run": create → save → run without waiting for confirmation. Build once.

When asked to "start from the current screen": use screenshot + Read + `ui_describe` to understand the screen → design steps.

## Rules

- `id` = filename (without extension) = kebab-case (e.g. `home-tab-switch`)
- action/verify in natural language. Do not hardcode selectors or IDs
- **1 action = 1 step** (to pinpoint failure location)
- Recording AXLabel / accessibilityIdentifier in `note` improves execution accuracy. **Do not write coordinates** (they differ by device)
- For structured hints, use `target` and `hints`. `note` is free text; `hints` are the best method per environment variant
- `hints[].method` uses only `tap-id` / `tap-label` / `touch-coordinate`
- If coordinates must be retained, store them as `hints[].method = "touch-coordinate"` rather than in `note`
- Up to one hint per environment variant in `hints`. Prefer updating/replacing over adding new entries
- Set `updated` when modifying a test
- Elements without accessibilityIdentifier set → add `.accessibilityIdentifier("screen.element-name")` to source and rebuild
- System UI (PhotosPicker, Share Sheet, SFSafariViewController, etc.) is inspectable through `sipi-ui`; include it only when stable on the target runtime, otherwise use pre-loaded data

## Step Types

- **action + verify**: Perform action and validate result (standard)
- **verify-only**: `{ "verify": "..." }` — check screen state only
- **action-only**: `{ "action": "..." }` — action only; PASS on exit 0

## preconditions

Check with `ui_describe | grep` before the test starts. If not met → SKIP the entire test (not FAIL).

## optional Steps

Marked with `"optional": true`. Before execution, confirm the target element exists with `ui_describe` → skip if absent.

## Error Case Patterns

Prepare at least one error case for every happy path case.

| Pattern | ID suffix |
|---------|--------------|
| Validation error (empty input, invalid value) | `-empty`, `-invalid` |
| Cancel / abort | `-cancel` |
| Empty state / no data | `-no-results` |
| Boundary value | `-boundary` |

## Test Updates

Load existing JSON → confirm in Simulator → update only the changed steps → set `updated` → confirm PASS by re-running.

Do not over-accumulate `hints` manually. Prioritize updating/replacing existing hints for the same environment variant based on the method that passed verify during execution.

## Screenshots

One per step (after verify). `step-001.png`, `step-002.png`... (zero-padded to 3 digits).
