# Test Execution, Build, and Result Verification

For full field definitions of the JSON format, see `../references/json-reference.md`.

## Build & Install

See `../../sipi-common/docs/build.md` for details.

- If `build` is present in config.json → clean build → install. If absent → use existing app
- Build failure: record `build-error` in run.json + all tests set to `passed: false`

## Execution Steps

### 1. Create Run Directory

```bash
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
DEVICE_SHORT=$(axe list-simulators | grep "$UDID" | awk -F'|' '{print $2}' | xargs | tr '[:upper:]' '[:lower:]' | tr -d ' ()' | tr -s '-')
COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "nogit")
git diff --quiet 2>/dev/null || COMMIT="${COMMIT}-dirty"
RUN_DIR=".simpilot/runs/${TIMESTAMP}_${DEVICE_SHORT}_${COMMIT}"
```

Also include the `ui-driver.md` shell prelude in this same Bash call before the first UI operation.

### 2. Launch App

```bash
xcrun simctl terminate $UDID $BUNDLE_ID 2>/dev/null
xcrun simctl launch $UDID $BUNDLE_ID
sleep 2
```

### 3. Step Execution Loop

Execution order for each step (**strictly required**):

1. `ui_describe` — get current screen state
2. Execute action via fallback chain
3. `sleep` (wait for animations)
4. verify with `ui_describe | grep`
5. `ui_screenshot "$RUN_DIR/$TEST/<step-file>.png"` — capture screen after verify
6. On failure, retry (up to max-retries times; go back to step 1 and restart from describe-ui)


When hints are present, first try the one matching environment variant (`device-class` + `device-name` + `ios` + `orientation`). Use only `tap-id` / `tap-label` / `touch-coordinate` for the hint's `method`. If it fails, fall back to the normal fallback chain. The normal search order follows patterns.md, but for hint retention, prioritize reproducibility: `tap-id` > `tap-label` > `touch-coordinate`. If `tap-id` succeeds, replace any existing `tap-label` / `touch-coordinate`; if `tap-label` succeeds, replace any existing `touch-coordinate`.

**Conditional wait** (preferred over fixed sleep):
```bash
MAX_WAIT=3; ELAPSED=0
while [ "$(awk "BEGIN{print ($ELAPSED < $MAX_WAIT)}")" -eq 1 ]; do
  ui_describe --expect "expected-label" 2>/dev/null | grep -q "expected-label" && break
  sleep 0.3; ELAPSED=$(awk "BEGIN{print $ELAPSED + 0.3}")
done
```

**grep patterns** (`&&` chaining is prohibited):
```bash
ok=true
echo "$UI" | grep -q '"AXLabel" : "Info"' || ok=false
echo "$UI" | grep -q '"AXLabel" : "Settings"' || ok=false
[ "$ok" = "true" ] && PASSED=true
```

## Hint Update Rules

After each step where verify succeeds, determine whether to update `hints` for that step. Do not update `hints` when verify fails.

### Determining the Environment Variant

The environment variant for a run is represented by:

- `device-class`: `iphone` / `ipad`
- `device-name`: e.g. `iPhone 16 Pro`
- `ios`: up to `major.minor`. e.g. `18.3`
- `orientation`: `portrait` / `landscape`

### Which Method to Record

Record only the **single method that ultimately passed verify** for that step.

- Passed with `ui_tap_id ...` → `tap-id`
- Passed with `ui_tap_label ...` → `tap-label`
- Passed with `axe touch ...` → `touch-coordinate`
- Passed with coordinate action after screenshot confirmation → `touch-coordinate`

Methods that were tried but failed are not saved in `hints`.

### Update Algorithm

1. Search the step's `hints` for a hint with the same environment variant
2. If no existing hint, add one new hint
3. If an existing hint exists and the successful method is the same, do not add; update `value` / `last-used` / `note` instead
4. If the existing hint is `touch-coordinate` and `tap-label` succeeds this time, replace it
5. If the existing hint is `tap-label` or `touch-coordinate` and `tap-id` succeeds this time, replace it
6. If the existing hint is stronger, do not replace it. Do not update `last-used` either

### Write-back Timing

- Do not write back after every step during testing
- After test completion, update `tests/<id>.json` once, reflecting only `passed: true` steps
- Hint updates for successful steps are allowed even for FAIL tests
- However, if there is any concern about the overall JSON integrity, do not write back; notify the user in the results display

### Writing the note

Keep the `note` short when updating a hint. Examples:

- `updated from label to id`
- `same method, value refreshed`
- `landscape on iPad`

## Failure Recording Procedure

For steps with `passed: false`, record the following in result.json.

### failure-type

Choose one failure classification:

| Value | Criteria |
|----|---------|
| `"action"` | Could not reach the action target after trying all fallback chain stages |
| `"verify"` | Action completed but the verification condition was not found with `describe-ui \| grep` |
| `"timeout"` | Exceeded the conditional wait limit |

### describe-ui-snapshot

Record up to the first 50 lines of `ui_describe` output at the point of failure. When the failed check was looking for a specific string, call `ui_describe --expect "<string>"` so the native bridge can supply System UI details if AXe returned a partial tree.

```bash
# Example recording on verify failure
UI=$(ui_describe --expect "expected-label" 2>/dev/null | head -50)
# → store in describe-ui-snapshot in result.json
```

### attempted-methods

Record the action methods tried in that step in normalized form. Record only the method type and target value, not raw commands.

```json
"attempted-methods": [
  { "method": "tap-label", "value": "Actions" },
  { "method": "tap-id", "value": "actions-menu" },
  { "method": "touch-coordinate", "value": "200,400" }
]
```

For input operations (`axe input`, `clipboard paste`, etc.), use `"input"` as the method and record only the target field name in value (do not record the input value itself).

### Cases Not to Record

- Steps with `passed: true` → no recording needed
- Steps with `skipped: true` → skipped due to prior step failure, no recording needed
- action-only steps (no verify) that exit 0 → PASS, no recording needed

## Result Writing

The `steps` array in result.json must correspond 1:1 with the `steps` array in the test definition (`tests/<id>.json`). Every test step produces exactly one result entry, regardless of whether a screenshot was taken.

- Accumulate each step's outcome (passed/failed/skipped, screenshot path, verify results, failure details) during execution and write the array as-is after the test completes
- Do not reverse-engineer the steps array from screenshot file counts or filename globs
- Optional steps that were skipped still produce an entry: `{ "passed": true, "skipped": true, ... }`
- Verify-only steps (no `action`) still produce an entry with `passed` and `verify`
- After writing, confirm `len(result.steps) == len(test.steps)`; if they differ, warn before proceeding

## Error Recovery

- **Retry**: Re-confirm with `ui_describe`, then re-execute the same action
- **Alert blocking**: Detect AXDialog before each step → get button label → tap
- **Crash**: App not found in describe-ui → terminate+launch → FAIL the affected step, SKIP the rest
- **iPad-specific issues**: See docs/patterns.md "App Launch" (iOS 18.x foreground, iOS 26 DockFolderViewService)

## review Criteria

- Coordinate fallback with verify OK → `passed: true` (record coordinate usage in `note`)
- Succeeded after retry → `passed: true` (record retry count in `note`)
- Closed alert and step succeeded → `passed: true` (record alert content in `note`)
- Only when success or failure truly cannot be determined → `review: true` (always record reason in `note`)

Coordinate fallback used for 2 or more steps in the same test → issue a warning after execution. Test level: if any step has `review: true` → the entire test is also `review: true`.

## optional Steps

Before execution, confirm the target element exists with `ui_describe` → if absent, set `passed: true, skipped: true`.

## preconditions

Check each condition with `ui_describe | grep`. If not met → SKIP the entire test.

## Video Recording

When config.json has `"record-video": true`: `axe record-video --udid $UDID --output "$RUN_DIR/$TEST/recording.mp4" &` → after test completion, send `kill -INT`.

## Device Resolution

1. List with `xcrun simctl list devices available`
2. Filter by model/runtime ("iOS 17" → latest 17.x)
3. Prefer latest runtime and Booted. If no match → `xcrun simctl create`

### Multi-device

Share SESSION → issue separate Bash commands to each device simultaneously → display summary after all complete.

## Suite Execution Details

- Build once → run tests sequentially (show progress) → display results
- `stop-on-failure: true` → stop on failure
- `reset-between-tests: true` → restart app between tests (caution with iPad iOS 26)
- Duplicate test IDs: add suffix to directory (`login/`, `login-2/`)

## Results Display

Table summary → FAIL details → Notes summary → improvement suggestions.

| Event | Suggestion |
|------|-----|
| Unexpected alert | Add optional step |
| verify mismatch but different text matched | Update verify |
| Coordinate fallback 2 or more times | Add accessibilityIdentifier |

On failure guidance: display failure details / open report.html / re-run failed tests.

## Final Check for run.json / result.json

Before generating the report, always confirm that the JSON under `.simpilot` matches `../references/json-reference.md`.

- `config.json` required keys: `app`
- `tests/*.json` required keys: `id`, `title`, `steps`
- `suites/*.json` required keys: `name`, `tests`
- `devices/*.json` required keys: `name`, `devices`
- `run.json` required keys: `started`, `device`, `tests`, `summary`
- `result.json` required keys: `id`, `passed`, `duration`, `steps`
- `result.json` step `verify` must be array format: `[{ "check": "...", "found": true }]` — never a plain string
- `result.json` step `screenshot` should name the file: `"screenshot": "step-001.png"`
- `run.json` `tests` must be array of objects: `[{ "id": "...", "passed": true, "duration": N }]` — never a plain string array
- Timestamps must be ISO 8601 with timezone offset. Example: `2026-03-12T23:09:09+09:00`
- Prohibited: custom keys such as `timestamp`, `total_tests`, `results`, `test_id`, `status`, `duration_seconds`, `ios_version`
- Prohibited: putting a display name in `device`. `device` is the UDID; the display name goes in `device-name`

After saving, always run the following:

```bash
SKILL_ROOT="$HOME/.agents/skills/sipi-test"
[ -d "$SKILL_ROOT" ] || SKILL_ROOT="$HOME/.claude/skills/sipi-test"
swift "$SKILL_ROOT/scripts/validate_simpilot_results.swift" .simpilot
```

- `OK` → generate report
- Errors present → fix the JSON before generating the report

## HTML Report

Generate `report.html` using the bundled script:

```bash
swift "$SKILL_ROOT/scripts/generate_test_report.swift" "$RUN_DIR"
open "$RUN_DIR/report.html"
```

The script reads `run.json` and each `result.json`, then writes a self-contained `report.html`. See `report.md` for the template reference if manual adjustments are needed.
