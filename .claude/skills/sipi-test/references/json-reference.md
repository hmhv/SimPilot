# JSON File Reference

The v2 file schema under `.simpilot/`. Per-action JSON shapes live in
`actions.md`; this file covers the structure around them.

## Common Rules

- Test ids use kebab-case.
- Run/result timestamps use ISO 8601 with timezone offset.
- Steps use explicit objects. Natural-language action strings are not valid v2.

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
    report.html                  # only with --html, or `sipi report <run-dir>`
    junit.xml                    # only with --junit, or `sipi report <run-dir> --junit`
    logs.ndjson
    logs.stderr.txt              # only when stderr is non-empty
    crash-reports.json           # only when matching reports exist
    crash-reports/               # copied .ips/.crash files
    <test-id>/
      result.json
      trace.jsonl
      fixture-manifest.json      # when fixtures are used
      container-before.json      # primary app data container; when capture succeeds
      container-after.json       # primary app data container; when capture succeeds
      container-diff.json        # primary app data container; when both succeed
      recording.mp4              # only with `record-video` / --record-video
      step-NNN.png
      step-NNN.describe-before.json    # describe-ui tree, see below
      step-NNN.describe-after.json
  verify/<timestamp>_<description>/
    summary.json
    checks.json
    findings.json
    <variant>/NNN_<check>.png    # iphone-light / iphone-dark / ipad-light / ipad-dark
    report.html                  # only with `finalize --html`, or `sipi verify-report`
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

| Field | Type | Required |
|---|---|:---:|
| `app` | string | Yes |
| `step-delay` | number | No |
| `max-retries` | int | No |
| `keep-runs` | int | No |
| `record-video` | bool | No |
| `network-condition-provider` | absolute path string | No |
| `capture-logs` | bool | No (default true) |
| `log-predicate` | string | No |
| `capture-container-diff` | bool | No (default true) |
| `build` | object (`project` / `scheme` / `configuration`) | No |

The harness consumes `app`, `step-delay`, `max-retries`,
`network-condition-provider`, `capture-logs`, `log-predicate`,
`capture-container-diff`, `record-video`, and `keep-runs`. `build` drives the
build step (see `../../sipi-common/docs/build.md`; all sub-keys optional,
`"build": {}` enables auto-detection). Log and container-diff capture default to
true.

`record-video: true` records every test to `<test-id>/recording.mp4` (H.264,
started before fixtures and launch, finalized before `result.json` is written)
and names it in the result's `video` field; `--record-video` on the run command
turns it on for one run. A recorder that cannot start is an `evidence-warnings`
entry, never a failed test.

`keep-runs: N` deletes the oldest completed runs under `runs/` after a run so
at most N remain, newest first. A candidate must have the
`yyyy-MM-dd_HHmmss_…` name the harness writes **and** a `run.json` with a
`finished` timestamp — so a folder parked under `runs/`, and a run another
`sipi` process is still writing, are both left alone. A run that aborted (a
launch that failed, a result that could not be written) is stamped `finished`
on the way out, with `run aborted: …` in `evidence-warnings`, so it is
reclaimable too. The run just written is never removed, and a run sent to an
explicit `--run-dir` prunes nothing. Unset or 0 keeps everything.

## tests/&lt;id&gt;.json

```json
{
  "id": "login-flow",
  "title": "Login Flow",
  "tags": ["smoke"],
  "fixtures": [
    { "source": "fixtures/account.json", "destination": "Documents/Inbox/account.json" }
  ],
  "steps": [
    {
      "id": "tap-sign-in",
      "action": { "type": "tap", "selector": { "id": "auth.sign-in" } },
      "verify": { "contains": ["Dashboard"], "absent": ["Sign In"] },
      "wait": 3
    }
  ]
}
```

Top level:

| Field | Type | Required |
|---|---|:---:|
| `id` | string | Yes |
| `title` | string | Yes |
| `app` | string | No |
| `tags` | string[] | No |
| `fixtures` | Fixture[] | No |
| `steps` | Step[] | Yes |
| `created` / `updated` | string | No |

Step:

| Field | Type | Required |
|---|---|:---:|
| `id` | string | No |
| `action` | Action | No* |
| `verify` | Verify | No* |
| `optional` | bool | No |
| `wait` | number | No |
| `note` | string | No |

\* At least one of `action` or `verify` is required.

Fixture:

| Field | Type | Required | Description |
|---|---|:---:|---|
| `source` | relative path | Yes | Source beneath the `.simpilot` workspace |
| `destination` | relative path | Yes | Destination beneath the selected storage root |
| `group-id` | string | No | Target an App Group instead of the data container |
| `files-app` | bool | No | Use experimental Files.app File Provider Storage |
| `storage` | absolute candidate path | No | Disambiguates `files-app`; must come from `sipi files-app candidates` |

Fixtures are applied before app launch and restored after the test, with the app
terminated for both mutations. Recovery metadata is persisted before each copy,
so an interrupted run leaves a usable manifest. `--no-launch` cannot be combined
with fixtures. `group-id` and `files-app: true`
are mutually exclusive. Absolute/traversing source or destination paths are
validation errors.

Files.app fixtures must be verified through the app UI. `container-files` and
the automatic container diff cannot read File Provider Storage.

`wait` is the **verify poll timeout** in seconds (default 3) — how long the
harness re-polls all verify inputs, including `describe-ui` and
`container-files`, before failing the step. It applies only to steps that have a
`verify` block, and it is not a pre-action sleep. For a deliberate pause, use a
`wait` *action*.

## Action types

Full JSON shapes and constraints: `actions.md`.

| Type | Requires | Notes |
|---|---|---|
| `tap` | `selector` or `point` | |
| `double-tap` | `selector` or `point` | Inside the system double-tap window |
| `long-press` | `selector` or `point` | `duration` hold, default 0.5s |
| `set-text` | `text` + `selector`/`point` | **Default for putting content in a field** |
| `type` | `text`, focused field | Only when the keystrokes are the subject |
| `key` | `usage` | |
| `key-combo` | `modifiers`, `key` | |
| `key-sequence` | `keycodes` | `delay` between presses |
| `button` | `button` | `home`, `lock`, `side_button`, `app_switcher`, `siri`, `swipe_home` |
| `swipe` | `start`, `end` | |
| `drag` | `start`, `end` | `steps` 1…1000 (enforced), `duration` |
| `gesture` | `preset` | `scroll-*`, `swipe-from-*-edge` |
| `pinch` | `direction` | `in` = zoom out, `out` = zoom in |
| `multitouch` | two `points`, `phase` | Only for non-pinch two-finger gestures |
| `slider` | `selector` (**`id` or `label` only**), `value` 0…100 | `tolerance`; drags then verifies AXValue. A `point` is rejected |
| `orientation` | `orientation` | |
| `crown` | `delta` | Apple Watch only |
| `wait` | — | `duration`, default 1s |
| `open-url`, `privacy`, `push`, `location`, `appearance`, `content-size`, `increase-contrast`, `status-bar`, `launch`, `terminate`, `network-condition` | varies | Simulator controls |
| `biometrics`, `display-state`, `memory-warning` | varies | Device state, Xcode 27+ |

## Selector

Exactly one of:

```json
{ "id": "auth.sign-in" }
{ "label": "Sign In" }
{ "value": "42" }
```

Optional `element-type` (string) restricts the match to an accessibility type
such as `Button` or `Switch`.

## Point

```json
{ "x": 0.5, "y": 0.8, "unit": "norm" }
{ "x": 200, "y": 700, "unit": "pixel" }
```

`unit` is `norm` (0…1, the default) or `pixel` (logical screen points — the same
space as `describe-ui` `frame`, not device/retina pixels). `sipi validate`
rejects any other unit, `norm` coordinates outside 0…1, and negative `pixel`
coordinates.

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

- `contains` / `absent`: every string must appear / must not appear in
  `describe-ui`.
- `matches` / `not-matches`: every regex must match / no regex may match.
- Patterns use search semantics, like grep; anchor with `^` / `$` for a whole
  string. An uncompilable pattern is a validation error, not a run-time surprise.
- Use strings that prove the new state, not static chrome.

### Container-file form

`container-files` asserts persisted app data and can be combined with UI and
element conditions:

```json
{
  "container-files": [
    {
      "path": "Library/Application Support/state.json",
      "format": "json",
      "key-path": "$.loggedIn",
      "equals": true
    },
    {
      "path": "Documents/export.sqlite",
      "format": "sqlite",
      "query": "select count(*) as count from items",
      "equals": "[{\"count\":3}]"
    }
  ]
}
```

Fields: `path` (required), optional `group-id`, `format` (`metadata`, `text`,
`json`, `plist`, `sqlite`), `key-path`, read-only `query`, and the assertions
`exists`, `size`, `sha256`, `equals`. At least one assertion is required.
Paths are relative and may not contain traversal or symlinks. SQLite queries run
with sqlite3 safe mode as well as read-only mode. `equals` is invalid with
`format: "metadata"`; `exists: false` cannot be combined with value, size, or
hash assertions. If `format` is omitted, it defaults to `metadata` when no
`equals` assertion is present and `text` when `equals` is present. With
`format: "text"`, or with `format` omitted, `equals` must be a string. An
`equals` comparison trims leading and trailing whitespace on both sides, so a
file that ends in a newline still matches an expectation that does not. A
`format: "text"` assertion requires the file to be valid UTF-8; use `sha256` or
`format: "metadata"` for binary files.

With no `group-id`, the path is in the app's primary data container. With
`group-id`, it is in that App Group. There is no Files.app target: verify a
Files.app fixture through UI state instead.

### Element form

`elements` asserts about ELEMENTS rather than the serialized text, which is what
makes "the button is disabled" or "there are exactly five rows" expressible:

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

Every node in a `describe-ui` tree (including the `step-NNN.describe-*.json`
artifacts) carries `AXLabel`, `AXValue`, `role_description`, `role`, `subrole`,
`type`, `AXUniqueId`, `enabled`, `frame{x,y,width,height}`, `children`, and:

| Field | Type | Description |
|---|---|---|
| `hitPoint` | `{x,y}` | A point ON the screen that reaches this element. Present only when the element can be touched |
| `onscreen` | bool | Whether any part of the element is currently visible |

`frame` is the element's own report and is not a tap target: it can extend past
the display, and an element inside a cross-process view (a share sheet) reports
a frame in that view's coordinate space, not the screen's. Read `hitPoint` when
a coordinate is needed, and `onscreen` to tell "scrolled away" from "absent".

Selector fields — at least one required, ANDed:

| Field | Type | Description |
|---|---|---|
| `id` | string | Exact `AXUniqueId` |
| `label` | string | Exact `AXLabel` |
| `value` | string | Exact `AXValue` |
| `element-type` | string | Accessibility type such as `Button` or `Cell` |

Assertion fields — all optional; a bare selector means "must exist":

| Field | Type | Description |
|---|---|---|
| `exists` | bool | Whether any element must match (default true) |
| `enabled` | bool | Required enabled state for every match |
| `value-equals` | string | Required exact `AXValue` for every match |
| `value-matches` | string | Regex over every match's `AXValue` (search semantics) |
| `count` | int | Exact number of matches |
| `min-count` / `max-count` | int | Bounds on the number of matches |
| `min-width` / `min-height` | number | Minimum frame extent in points — the assertion form of the 44pt touch-target rule |

String comparisons are exact after trimming; use `contains` for substring
matching. Asserting a property of an element that does not exist FAILS ("no
element matched") rather than passing over an empty set, so an element condition
can never green a step vacuously.

`sipi validate` rejects a condition with no selector, contradictory counts
(`min-count` above `max-count`, `count` alongside `min-count`/`max-count`), and
`exists: false` paired with a property assertion.

## suites/&lt;name&gt;.json

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

Required: `name`, `tests` (test ids, each resolved to
`<workspace>/tests/<id>.json`). Optional: `description`, `settings`
(`stop-on-failure` default `false`, `reset-between-tests` default `true`). The
filename must match `name` — `sipi validate` enforces it.

## result.json

Written by the harness; never authored by hand.

| Field | Type |
|---|---|
| `id` | string |
| `passed` | bool |
| `review` | bool |
| `duration` | number |
| `steps` | ResultStep[] |
| `artifacts` | object mapping artifact labels to relative paths |
| `cleanup-error` | string describing failed fixture restoration |
| `video` | `recording.mp4`, only when the test was recorded and the file finalized |

Each result step may include `passed`, `duration`, `action`, `screenshot`,
`screenshots.before`, `screenshots.after`, `verify`, `attempted-methods`,
`describe-ui-snapshot`, `skipped`, `note`, and `failure-type`.

`failure-type` is `action` (selector/element resolution failure, or a thrown step
error) or `verify` (a verify row unsatisfied at the wait deadline, or a
verify-only step that failed). `sipi validate` also accepts `timeout`, but the
harness never emits it — a wait-deadline miss is reported as `verify`.

`failure-type` names the category. Where the cause is recorded depends on which
category it is:

| Failure | Where the cause is |
|---|---|
| Something threw (`failure-type: action`, and a verify that errored) | `note` carries the error text — e.g. the resolver's "Multiple (3) accessibility elements matched label 'Delete'…". A suppressed-retry reason takes that slot when there is one, since it explains both the failure and why no retry followed |
| A verify condition simply did not hold | `verify[]` — each row's `check` and `found`. Nothing threw, so `note` may be absent entirely unless the spec author wrote one |

Both kinds also appear in `trace.jsonl` as a `step-attempt-error` event, once per
failed attempt.

Every one of these fields describes the **last** attempt, not an earlier one:
a step that failed at the action stage on its retry carries no verify rows from
the attempt before it, and vice versa.

Artifact paths are constrained relative links within the run directory. A
successful fixture restoration leaves an empty manifest and removes its backup
directory. A non-empty manifest plus `cleanup-error` is recovery state; preserve
both it and its sibling backup directory.

## run.json evidence

The harness may add these run-level fields:

| Field | Type | Description |
|---|---|---|
| `artifacts` | object | Relative links such as `logs.ndjson`, `logs.stderr.txt`, or `crash-reports.json` |
| `evidence-warnings` | string[] | Best-effort capture problems that do not alter the test verdict |

`logs.ndjson` contains JSON-object records only; the `log` command's filter
banner and completion footer are removed. Unless `log-predicate` replaces it,
the default predicate covers the run bundle ID and all test-level `app`
overrides. Crash evidence is collected for those same exact bundle IDs and only
from the run's start time onward. Automatic container snapshots cover only each
test app's primary data container, not App Groups or Files.app storage. They
contain metadata and hashes, not file contents; per-file read failures are
recorded in each snapshot's `errors` array and surfaced as evidence warnings. A
whole-snapshot failure also becomes an evidence warning and the corresponding
artifact is omitted.

## summary.json

The compact result for agents and CI:

```json
{
  "status": "fail",
  "run-id": "2026-06-26_104522_iphone16_abc1234",
  "started": "2026-06-26T10:45:22.123+09:00",
  "finished": "2026-06-26T10:46:12.456+09:00",
  "device": { "name": "iPhone 16 Pro", "runtime": "iOS 26.0", "udid": "..." },
  "counts": { "total": 1, "passed": 0, "failed": 1, "review": 0, "skipped": 0 },
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
  "report": "report.html",
  "junit": null
}
```

`report` names the HTML page only when it exists; it is `null` on a run that was
not asked for one. `junit` follows the same rule for `junit.xml` (`--junit`, or
`sipi report <run-dir> --junit` afterwards).

`status` is the gate field for **test outcomes**. `started`, `finished`,
`device`, and `report` are always present. In each `top-failures` entry `action`
is always present (defaults to `(verify-only)` for a verify-only step);
`missing`/`verify`, `matched`, and `screenshot` appear only when applicable.

**`status` does not cover environment cleanup.** The harness writes `run.json`,
`summary.json` (and `report.html` when asked for) *before* the end-of-run restore — deliberately,
so a cleanup failure cannot destroy the artifacts. A run whose tests all passed
therefore keeps `"status": "pass"` even when the restore afterward fails and
leaves the simulator dirty. The failure surfaces only as a **non-zero CLI exit
code**. CI and agents must gate on the exit code as well as on `status`; treat a
`pass` with a non-zero exit as "tests passed, device state unreliable" and reset
before the next run.

Fixture restoration is different because it happens inside a test: failure sets
that test's `passed` to false, makes summary `status` `fail`, and writes
`cleanup-error`, while the CLI may still exit 0. Such a failure can leave
`top-failures` empty because no test step failed; inspect `run.json` and the
test's `result.json` whenever summary status is not `pass`.

## Status Display

Two related but distinct mappings — the badge is per step/test, `status` is the
run-level gate.

**Per-step / per-test badge**, in order:

1. `passed && skipped` → **SKIP**
2. `!passed` → **FAIL**
3. `review` → **REVIEW** — reserved. The harness reads `review` off a step result
   but never sets it, so nothing `sipi run-test` / `run-suite` produces reaches
   this row today
4. else → **PASS**

**Run-level `summary.json` `status`**, in order (a failed step is `fail` even
when another step is marked review):

1. `failed > 0` → `fail`
2. `review > 0` → `review`
3. `total == 0` → `empty`
4. else → `pass`

The verify skill's report uses a separate "All OK" / "Issues Found" pill driven
by `findings.json` — a different command, documented in
`../../sipi-verify/docs/report.md`.
