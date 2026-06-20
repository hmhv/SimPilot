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
DEVICE_SHORT=$(xcrun simctl list devices | grep "$UDID" | sed -E 's/^[[:space:]]*//; s/ \(.*//' | tr '[:upper:]' '[:lower:]' | tr -d ' ()' | tr -s '-')
COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "nogit")
git diff --quiet 2>/dev/null || COMMIT="${COMMIT}-dirty"
RUN_DIR=".simpilot/runs/${TIMESTAMP}_${DEVICE_SHORT}_${COMMIT}"
```

Also include the `ui-driver.md` shell prelude in this same Bash call before the first UI operation.

### 2. Launch App

```bash
mkdir -p "$RUN_DIR/$TEST"
xcrun simctl terminate $UDID $BUNDLE_ID 2>/dev/null
xcrun simctl launch $UDID $BUNDLE_ID
sleep 2
```

### 3. Step Execution Loop

**Run is read-only on the spec.** During a run, do not edit test steps, verify strings, `config.json`, or app source. If verify fails, record FAIL and stop trying to make it pass. The only sanctioned write-back during a run is the post-run hint update (see "Hint update" below), and it never flips a step from `passed: false` to `passed: true`.

Each step follows these invariants (not a rigid fixed sequence — they are the properties every step must satisfy, and the reasons):

- **Describe BEFORE acting.** Start every step with `ui_describe` to read the current screen, and choose the action target from that tree — never act on an assumed screen state. Acting on a stale assumption is the classic cause of fake-success taps and mis-targeted coordinates.
- **Screenshot AFTER verify.** Capture `ui_screenshot "$RUN_DIR/$TEST/<step-file>.png"` once the verify check has run, so the saved image reflects the verified state.
- **Prefer a conditional wait over a fixed `sleep`.** A fixed sleep either wastes time or races the animation; poll for the expected state instead (see below).
- **Verify via `ui_describe | grep`, not screenshots.** Screenshots are subjective and non-reproducible across runs and reviewers; only a grep on the describe-ui tree is a mechanical, repeatable check.
- **Honor step semantics.** A verify-only step (no `action`) just greps current state. An action-only step (no `verify`) PASSes on exit 0. (Definitions: `create.md`.)

When hints are present, first try the one matching environment variant (`device-class` + `device-name` + `ios` + `orientation`). Use only `tap-id` / `tap-label` / `touch-coordinate` for the hint's `method`. If it fails, fall back to the normal fallback chain in `../../sipi-common/docs/patterns.md`. (Hint retention priority is covered under "Hint update" below.)

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

### Strong vs weak verify

- **WEAK**: grepping a string that was already present BEFORE the action — static chrome, an unchanging tab label, a fixed navigation title. Such a check passes whether or not the action did anything, so it cannot catch a regression.
- **STRONG**: assert the NEW state the action produces, and where feasible assert that the OLD state is gone (e.g. after switching to Settings, confirm a Settings-only label appears AND the Home-only label is absent).

Before recording PASS, state a one-line **negative control**: name the substring you matched and why it would be absent if the feature were broken. If you cannot state it, set `review: true` and put the reason in `note` rather than claiming a PASS.

## Hint update

After a step's verify succeeds, record the single method that worked so future runs are reproducible. One principle block:

- **Rank by reproducibility**: `tap-id` > `tap-label` > `touch-coordinate`. Record only the *single* method that ultimately passed verify (`ui_tap_id`→`tap-id`, `ui_tap_label`→`tap-label`, `ui_tap_xy` / `sipi tap`→`touch-coordinate`); methods that were tried but failed are not saved.
- **One hint per environment variant** (`device-class` + `device-name` + `ios` + `orientation`). Update/replace the matching hint rather than accumulating new ones.
- **Replace only with an equal-or-stronger method.** If the successful method outranks the stored one, replace it and refresh `value` / `last-used` / `note`. Same method → refresh `value` / `last-used` / `note`. **Never downgrade**, and never refresh `last-used` when this run only succeeded with a weaker method than the one already stored.
- **Write back once after the test**, not per step — update `tests/<id>.json` reflecting only `passed: true` steps (allowed even when the overall test is FAIL). Never touch `hints` for a step whose verify failed.
- **Integrity caveat**: if there is any concern about overall JSON integrity, do not write back; note it in the results display.

Keep the `note` short. Examples: `updated from label to id`, `same method, value refreshed`, `landscape on iPad`.

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

Record up to the first 50 lines of `ui_describe` output at the point of failure. When the failed check was looking for a specific string, call `ui_describe --expect "<string>"` so `sipi describe-ui` runs its deeper grid pass and includes System UI details when the fast frontmost tree misses the expected text.

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

For input operations (`sipi type`, `clipboard paste`, etc.), use `"input"` as the method and record only the target field name in value (do not record the input value itself).

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

- **Retry**: Re-confirm with `ui_describe`, then re-execute the **same action** and re-check the **same verify string**. Do not change the verify condition or the target between retries within a run — that is a FIX, not a retry. If the unchanged verify still fails after `max-retries`, record FAIL
- **Alert blocking**: Detect AXDialog before each step → get button label → tap
- **Destructive-confirm alert**: After tapping a destructive trigger (Trash/Delete) that presents a `UIAlertController`, wait for the alert to settle before tapping confirm — the confirm button can be absorbed if tapped mid-presentation. Use a conditional wait on the confirm label (or a brief `sleep 0.5`), then re-`describe-ui` and tap. See `../../sipi-common/docs/patterns.md` "Alert / Confirmation Dialog"
- **Crash**: App not found in describe-ui → terminate+launch → FAIL the affected step, SKIP the rest
- **iPad-specific issues**: See `../../sipi-common/docs/patterns.md` "App Launch" (iOS 18.x foreground, iOS 26 DockFolderViewService)

## Review Criteria

- Coordinate fallback with verify OK → `passed: true` (record coordinate usage in `note`)
- Succeeded after retry → `passed: true` (record retry count in `note`)
- Closed alert and step succeeded → `passed: true` (record alert content in `note`)
- Only when success or failure truly cannot be determined → `review: true` (always record reason in `note`)

Coordinate fallback used for 2 or more steps in the same test → issue a warning after execution. Test level: if any step has `review: true` → the entire test is also `review: true`.

## Optional Steps and Preconditions

See `create.md` for the definitions. At run time:

- **Optional step**: confirm the target element exists with `ui_describe` → if absent, set `passed: true, skipped: true` (still produces a 1:1 result entry).
- **Precondition**: check each condition with `ui_describe | grep` → if not met, SKIP the entire test (not FAIL).

## Video Recording

When config.json has `"record-video": true`: `sipi record-video $UDID "$RUN_DIR/$TEST/recording.mp4" &` → after test completion, send `kill -INT` to the recording process to stop and finalize the file.

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

These are **post-run** suggestions — record the run's result first (a failing run is FAIL), then propose them for a separate FIX phase. Never apply them mid-run (see "Run is read-only on the spec").

| Event | Post-run suggestion |
|------|-----|
| Unexpected alert | Add an optional step |
| verify mismatch but different text matched | Correct the verify string in the FIX phase (this run is still FAIL) |
| Coordinate fallback 2 or more times | Add an accessibilityIdentifier |

On failure guidance: display failure details / open report.html / re-run failed tests.

## Final Check for run.json / result.json

`../references/json-reference.md` is the single authority for every key (and for the prohibited custom keys). After writing the JSON, validate against it, then run the mechanical gate until it shows OK:

```bash
sipi validate .simpilot
```

- `OK` → generate report
- Errors present → fix the JSON before generating the report (the validator rejects unknown keys, so any custom field will surface here)

## HTML Report

See `report.md`. Generate the self-contained report with the sole supported generator, then open it:

```bash
sipi report "$RUN_DIR"
open "$RUN_DIR/report.html"
```
