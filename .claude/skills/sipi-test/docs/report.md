# Run Output

Every run writes `run.json`, `summary.json`, and a `<test-id>/result.json` per
test. That is the result, and it is what to read.

`report.html` is a browser page for a person to page through, and it is NOT
written by default — rendering it costs time on every run and an agent has no
use for it. Ask for it when a human is going to look:

```bash
sipi run-test  … --html          # during the run
sipi run-suite … --html
sipi report "$RUN_DIR"           # afterwards, from the same artifacts
```

`sipi report` reads `run.json` and each `result.json`, writes `report.html`, and
rewrites `summary.json` so its `report` field names the page. There is no
manual/by-hand path — do not assemble the HTML or summary yourself.

## What the HTML report contains

Screenshots are embedded in `report.html` as **Base64 data URIs**. Logs, primary
app data-container snapshots/diffs, fixture manifests, and crash reports remain
separate sensitive files linked with relative paths, so move the whole run
directory when those artifacts must remain accessible. Its logical structure:

- **Run header** — suite name (or "Ad-hoc Run"), device name + runtime + commit, start time, and a summary bar of counts. Per-test durations are in the results table; the header carries no run total.
- **Evidence** — run-level warnings and links to normalized unified logs, log
  stderr, and the crash-report index when present.
- **Failure highlights** — failed steps first, before the full results table, with failure type, missing verify text, and attempted methods.
- **Results table** — one row per test in run order: status badge, test ID, duration, and notes (coordinate fallback, retries, etc.). The ID links to that test's detail section when one exists; a test with no screenshots, failure, artifacts, or cleanup error renders no section, so it is listed as plain text.
- **Step gallery** — for tests with screenshots or failures, a horizontal row of step thumbnails. Each card carries its step number, duration, the action it captured, and a verify tally (`✓2/2`) when the step asserted anything. Detail sections are ordered failures first, then review, then passes — the table keeps run order, the details lead with what went wrong. In practice `sipi run-test` / `run-suite` never mark a step for review, so the middle tier is empty for binary-produced runs (see the note under Badge / status).
- **Step detail** — for failed steps only: the action, each verify check (found / not-found), `failure-type`, and `attempted-methods`. A passing step, review-flagged or not, carries what it has on its card.
- **Test artifacts** — links to fixture recovery manifests and primary app
  data-container before/after/diff JSON, plus a visible fixture-cleanup error
  when restoration failed.
- **describe-ui snapshot** — a collapsible block with the first 50 lines of the `describe-ui-snapshot` field (the after-step describe-ui JSON) captured at the point of failure.
- **Lightbox** — clicking a screenshot opens it large with a caption naming the test, step, and action. The arrow keys walk the rest of that test's steps; Esc or a click closes it.

Screenshots are downscaled to 600px on the long side before embedding. That bounds the long side, so a portrait phone capture lands at 276x600 — a little short of 2x for a 200px thumbnail — in exchange for a report that stays a couple of MB instead of 17. A capture whose re-encode would come out no smaller is embedded unchanged, so the 600px figure is a target rather than a guarantee. The report follows the reader's light/dark colour scheme, with a toggle in the header that overrides it. The choice is stored in `localStorage`, which browsers scope per origin — for a `file:` document that is browser-dependent, so it may or may not carry to the next report you open, and a browser that refuses storage entirely just leaves the toggle working per page.

## summary.json

`summary.json` is the default result, for tools and agents. It includes:

- `status`: `pass`, `fail`, `review`, or `empty`
- `run-id`, `started`, `finished`
- `device`: name, runtime, and UDID
- `counts`: total, passed, failed, review, skipped
- `top-failures`: first failed step per failed test, including missing verify text and screenshot path when available
- `report`: `report.html` when that page exists, `null` when it does not

`summary.json` deliberately stays compact. Read `run.json` for run-level
`artifacts` and `evidence-warnings`, and each `<test-id>/result.json` for
per-test `artifacts` and `cleanup-error`. Evidence warnings do not change
`summary.json` `status`. A fixture restoration failure marks its test failed and
appears as `cleanup-error`, but does not by itself make the CLI exit non-zero;
inspect the result/report even when the process exits 0. A later run-level
environment cleanup failure can instead leave a passing summary and signal the
problem only with a non-zero exit code.

## Badge / status

The PASS / FAIL / REVIEW / SKIP badge mapping is defined by the Status Display
table in `../references/json-reference.md`.

REVIEW is the one badge the binary cannot currently produce: the harness reads a
`review` flag off each step result but never writes one, so `review` is always
false and the run-level `status` is never `review`. Treat the REVIEW row as
reserved rather than reachable until a step actually sets it.
