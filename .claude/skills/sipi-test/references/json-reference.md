# JSON File Reference

Specification for JSON files under `.simpilot/`. For everyday usage, see the project README.

## Directory Structure

```text
.simpilot/
  config.json
  tests/<id>.json
  suites/<name>.json
  devices/<name>.json
  runs/<run-id>/
    run.json
    report.html
    <test-id>/
      result.json
      step-NNN.png
      recording.mp4
  verify/<timestamp>_<description>/
    report.html
```

- `tests/`, `suites/`, and `devices/` are files intended for manual editing
- `runs/` and `verify/` are typically listed in `.gitignore`
- `verify/` output structure is defined in the sipi-verify skill (`../../sipi-verify/docs/report.md`)

## Common Rules

- Test IDs use kebab-case
- `tests/<id>.json` must have an `id` field matching the filename
- `suites/<name>.json` and `devices/<name>.json` must have names matching their filenames
- Run/result timestamps use ISO 8601 with timezone offset
  - Example: `2026-03-07T11:03:24-08:00`

### Prohibited custom keys

`sipi validate` rejects unknown keys, so do not invent fields. Use the keys defined in this document exactly. Common mistaken keys the validator rejects (with the correct key in parentheses):

- `timestamp` (use `started` / `finished` in `run.json`)
- `total_tests` (use `summary.total`)
- `results` (use `tests` in `run.json`, `steps` in `result.json`)
- `test_id` (use `id`)
- `status` (use the `passed` / `review` / `skipped` booleans; the report derives the display status from the Status Display table)
- `duration_seconds` (use `duration`)
- `ios_version` (use `device-runtime`)
- a display name in `device` — `device` is the UDID; the display name goes in `device-name`

This file is the single authority for keys; `../docs/run.md` and `../SKILL.md` point here rather than re-listing them.

## config.json

Path: `.simpilot/config.json`

```json
{
  "app": "com.example.myapp",
  "step-delay": 0.5,
  "max-retries": 2,
  "keep-runs": 20,
  "build": {
    "project": "MyApp.xcodeproj",
    "scheme": "MyApp"
  }
}
```

### Fields

| Field | Type | Required | Default | Description |
|---|---|:---:|---|---|
| `app` | string | Yes | - | Bundle ID of the app under test |
| `step-delay` | number | No | `0.5` | Wait time in seconds between steps |
| `max-retries` | int | No | `2` | Number of retries for a failing step |
| `keep-runs` | int | No | `20` | Number of run results to retain |
| `record-video` | bool | No | `false` | Set to `true` to record video |
| `build` | object | No | - | Pre-run build configuration |

### build

| Field | Type | Required | Default | Description |
|---|---|:---:|---|---|
| `project` | string | No | auto-detected | `.xcodeproj` or `.xcworkspace` |
| `scheme` | string | No | auto-detected | Build scheme |
| `configuration` | string | No | `"Debug"` | Build configuration |

- If `build` is present, the app is built before running
- Auto-detection order for `project`: `.xcworkspace` → `.xcodeproj` → `Package.swift`


## tests/<id>.json

Path: `.simpilot/tests/<id>.json`

One file per test.

```json
{
  "id": "home-tab-switch",
  "title": "Home Tab Switching",
  "tags": ["smoke", "navigation"],
  "steps": [
    {
      "verify": "Home screen is displayed",
      "target": {
        "screen": "home",
        "texts": ["Home"]
      }
    },
    {
      "action": "Tap the Settings tab",
      "verify": "Settings screen appears",
      "target": {
        "role": "tab",
        "ids": ["tab.settings"],
        "texts": ["Settings"],
        "screen": "root-tabs"
      },
      "hints": [
        {
          "device-class": "iphone",
          "device-name": "iPhone 16 Pro",
          "ios": "18.3",
          "orientation": "portrait",
          "method": "tap-id",
          "value": "tab.settings",
          "last-used": "2026-03-04T10:15:00-08:00"
        }
      ]
    }
  ],
  "created": "2026-03-04"
}
```

### Fields

| Field | Type | Required | Default | Description |
|---|---|:---:|---|---|
| `id` | string | Yes | - | Test ID |
| `title` | string | Yes | - | Display name |
| `app` | string | No | `app` from `config.json` | Per-test override |
| `tags` | string[] | No | `[]` | Tags |
| `steps` | Step[] | Yes | - | Step definitions |
| `preconditions` | string[] or object[] | No | `[]` | Preconditions before execution |
| `created` | string | No | - | Creation date (`YYYY-MM-DD`) |
| `updated` | string | No | - | Last updated date (`YYYY-MM-DD`) |

### Step

| Field | Type | Required | Default | Description |
|---|---|:---:|---|---|
| `action` | string | No | - | Operation to perform |
| `verify` | string | No | - | Verification condition |
| `optional` | bool | No | `false` | Skip if the target is not found |
| `note` | string | No | - | Additional notes |
| `target` | object | No | - | Hints for locating the UI element |
| `hints` | Hint[] | No | `[]` | Known-good interaction methods recorded from earlier runs |

- Omitting both `action` and `verify` is not allowed
- No `action` means verify-only
- No `verify` means action-only

### preconditions

String form:

```json
["Logged-out state is visible"]
```

Object form:

```json
[
  {
    "check": "Login screen is visible",
    "grep": "login_button"
  }
]
```

| Field | Type | Required | Description |
|---|---|:---:|---|
| `check` | string | Yes* | Human-readable condition |
| `description` | string | Yes* | Alias for `check` |
| `grep` | string | No | Optional search hint |

\* One of `check` or `description` is required.

### target

| Field | Type | Required | Default | Description |
|---|---|:---:|---|---|
| `role` | string | No | - | UI element type |
| `ids` | string[] | No | `[]` | Candidate accessibilityIdentifiers |
| `texts` | string[] | No | `[]` | Candidate display strings |
| `screen` | string | No | - | Screen name |
| `within` | string | No | - | Search scope hint |

### Hint

| Field | Type | Required | Default | Description |
|---|---|:---:|---|---|
| `device-class` | string | No | - | `iphone` / `ipad` etc. |
| `device-name` | string | No | - | Device name at the time of success |
| `ios` | string | No | - | iOS version at the time of success |
| `orientation` | string | No | - | `portrait` / `landscape` |
| `method` | string | Yes | - | `tap-id` / `tap-label` / `touch-coordinate` |
| `value` | string | No | - | Value corresponding to the method |
| `last-used` | string | No | - | Timestamp of last successful use |
| `note` | string | No | - | Additional notes |

- Only one hint is retained per environment variant
- An environment variant is defined by `device-class` + `device-name` + `ios` + `orientation`
- Updated only on successful verification
- Retention priority: `tap-id` > `tap-label` > `touch-coordinate`

## suites/<name>.json

Path: `.simpilot/suites/<name>.json`

```json
{
  "name": "regression",
  "description": "Core regression test suite",
  "tests": ["app-launch", "settings-toggle", "tab-navigation"],
  "settings": {
    "stop-on-failure": false,
    "reset-between-tests": true
  }
}
```

### Fields

| Field | Type | Required | Default | Description |
|---|---|:---:|---|---|
| `name` | string | Yes | - | Suite name |
| `description` | string | No | - | Description |
| `tests` | string[] | Yes | - | Ordered list of test IDs to run |
| `settings` | object | No | - | Execution settings |

### settings

| Field | Type | Required | Default | Description |
|---|---|:---:|---|---|
| `stop-on-failure` | bool | No | `false` | Stop the suite on first failure |
| `reset-between-tests` | bool | No | `true` | Relaunch the app between tests |

## devices/<name>.json

Path: `.simpilot/devices/<name>.json`

```json
{
  "name": "regression",
  "description": "iOS 17 and 18 baseline regression devices",
  "devices": [
    { "model": "iPhone 16 Pro" },
    { "model": "iPhone 15", "runtime": "iOS 17" },
    { "runtime": "iOS 18.3" }
  ]
}
```

### Fields

| Field | Type | Required | Default | Description |
|---|---|:---:|---|---|
| `name` | string | Yes | - | Device set name |
| `description` | string | No | - | Description |
| `devices` | Device[] | Yes | - | List of device conditions |

### Device

| Field | Type | Required | Default | Description |
|---|---|:---:|---|---|
| `model` | string | Conditional | - | Device model name |
| `runtime` | string | Conditional | - | e.g. `iOS 18.3` |
| `udid` | string | Conditional | - | Simulator UDID |

- At least one of `model` / `runtime`, or `udid` is required
- `model` alone uses the latest available runtime
- `runtime` alone selects from booted or available devices
- Specifying both `model` and `runtime` is an exact match
- Shortened versions like `iOS 17` match the latest `17.x`

## result.json

Path: `.simpilot/runs/<run-id>/<test-id>/result.json`

```json
{
  "id": "home-tab-switch",
  "passed": false,
  "duration": 12.3,
  "steps": [
    {
      "action": "Tap the Settings tab",
      "passed": true,
      "duration": 3.1,
      "screenshot": "step-001.png",
      "verify": [
        { "check": "Settings screen appears", "found": true }
      ]
    },
    {
      "action": "Tap the Home tab",
      "passed": false,
      "duration": 2.0,
      "screenshot": "step-002.png",
      "verify": [
        { "check": "Return to home screen", "found": false }
      ],
      "failure-type": "verify",
      "describe-ui-snapshot": "AXLabel: Settings\nAXLabel: General\n...",
      "attempted-methods": [
        { "method": "tap-label", "value": "Home" },
        { "method": "tap-id", "value": "tab.home" },
        { "method": "touch-coordinate", "value": "40,832" }
      ]
    }
  ]
}
```

### Fields

| Field | Type | Required | Default | Description |
|---|---|:---:|---|---|
| `id` | string | Yes | - | Test ID |
| `passed` | bool | Yes | - | Overall pass/fail result |
| `review` | bool | No | `false` | Includes a step with deferred judgment |
| `skipped` | bool | No | `false` | The entire test was skipped |
| `duration` | number | Yes | - | Total elapsed time |
| `video` | string | No | - | Video filename |
| `steps` | ResultStep[] | Yes | - | List of step results (1:1 with test definition steps) |

The `steps` array must have the same length as the test definition's `steps`. Every test step produces exactly one result entry, including optional steps that were skipped and verify-only steps.

### ResultStep

| Field | Type | Required | Default | Description |
|---|---|:---:|---|---|
| `action` | string | No | - | Operation that was performed |
| `passed` | bool | Yes | - | Step pass/fail |
| `duration` | number | No | - | Elapsed time |
| `screenshot` | string | No | - | Screenshot filename (single post-step capture, e.g. `step-001.png`) |
| `screenshots` | { before?: string, after?: string } | No | - | Before/after screenshot pair for visual diff steps. Use instead of `screenshot` when both a pre-action and post-action capture are needed |
| `verify` | Verify[] | No | - | Verification results; always array format in result.json |
| `note` | string | No | - | Additional notes |
| `review` | bool | No | `false` | Judgment deferred |
| `skipped` | bool | No | `false` | Optional step was skipped |
| `failure-type` | string | No | - | `action` / `verify` / `timeout` |
| `describe-ui-snapshot` | string | No | - | `describe-ui` output at failure (up to 50 lines) |
| `attempted-methods` | AttemptedMethod[] | No | - | Interaction methods that were tried |

### Verify

| Field | Type | Required | Default | Description |
|---|---|:---:|---|---|
| `check` | string | Yes | - | Verification condition |
| `found` | bool | Yes | - | Whether a match was found |
| `grep-match` | string | No | - | The actual string that was matched. **Strongly recommended** for any passed check so the PASS is auditable — but it is not schema-required |

### AttemptedMethod

| Field | Type | Required | Default | Description |
|---|---|:---:|---|---|
| `method` | string | Yes | - | `tap-label` / `tap-id` / `touch-coordinate` / `input` |
| `value` | string | No | - | Target value |

### Status Display

| Condition | Report Display |
|---|---|
| `passed: true` | PASS |
| `passed: true, review: true` | REVIEW |
| `passed: false` | FAIL |
| `passed: true, skipped: true` | SKIP |

`review: true` is used only when the outcome cannot be determined as either success or failure.

## run.json

Path: `.simpilot/runs/<run-id>/run.json`

```json
{
  "started": "2026-03-02T14:30:22-08:00",
  "finished": "2026-03-02T14:31:05-08:00",
  "device": "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX",
  "device-name": "iPhone 16 Pro",
  "device-runtime": "iOS 18.3",
  "session": "2026-03-02_143022",
  "profile": "regression",
  "commit": "abc1234",
  "tests": [
    { "id": "app-launch", "passed": true, "duration": 3.2 },
    { "id": "settings-toggle", "passed": true, "review": true, "duration": 5.4 },
    { "id": "tab-navigation", "passed": false, "duration": 8.1 }
  ],
  "summary": {
    "total": 3,
    "passed": 2,
    "failed": 1,
    "review": 1
  }
}
```

### Fields

| Field | Type | Required | Default | Description |
|---|---|:---:|---|---|
| `started` | string | Yes | - | Run start timestamp |
| `finished` | string | No | - | Run end timestamp |
| `device` | string | Yes | - | Simulator UDID |
| `device-name` | string | No | - | Device name |
| `device-runtime` | string | No | - | iOS version |
| `session` | string | No | - | Session ID |
| `suite` | string | No | - | Suite name used |
| `profile` | string | No | - | Device set name used |
| `commit` | string | No | - | Abbreviated git commit from `git rev-parse --short` (>= 7 chars; `-dirty` suffix appended when the working tree is dirty) |
| `build-error` | string | No | - | Build failure summary |
| `tests` | TestEntry[] | Yes | - | Summary of test results |
| `summary` | Summary | Yes | - | Aggregated counts |

### TestEntry

| Field | Type | Required | Default | Description |
|---|---|:---:|---|---|
| `id` | string | Yes | - | Test ID |
| `passed` | bool | Yes | - | Test pass/fail |
| `review` | bool | No | `false` | Includes a REVIEW result |
| `skipped` | bool | No | `false` | Test was skipped |
| `duration` | number | Yes | - | Elapsed time |

### Summary

| Field | Type | Required | Default | Description |
|---|---|:---:|---|---|
| `total` | int | Yes | - | Total count |
| `passed` | int | Yes | - | Number passed |
| `failed` | int | Yes | - | Number failed |
| `review` | int | No | `0` | Number in REVIEW |

## Type Conventions

- `int` and `number` in this document: JSON has a single `number` type. `int` indicates values that should be whole numbers; `number` allows decimals
- `bool` fields (`passed`, `review`, `skipped`, `optional`, etc.) must be JSON booleans (`true`/`false`), not strings
