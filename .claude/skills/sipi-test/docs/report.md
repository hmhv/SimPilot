# HTML Report Generation

`sipi run-test` and `sipi run-suite` generate the report automatically. To regenerate a report for an existing run directory, use:

```bash
sipi report "$RUN_DIR"
open "$RUN_DIR/report.html"
```

`sipi report` reads `run.json` and each `result.json`, then writes:

- `report.html`: self-contained browser report
- `summary.json`: compact machine-readable run summary for agents and CI

There is no manual/by-hand path — do not assemble the HTML or summary yourself.

## What the report contains

`report.html` is self-contained: all screenshots are embedded as **Base64 data URIs**, so the single file is portable on its own (it does not reference image files by relative path). Its logical structure:

- **Run header** — suite name (or "Ad-hoc Run"), device name + runtime + commit, start time, and a summary bar of counts. Per-test durations are in the results table; the header carries no run total.
- **Failure highlights** — failed steps first, before the full results table, with failure type, missing verify text, and attempted methods.
- **Results table** — one row per test in run order: status badge, test ID, duration, and notes (coordinate fallback, retries, etc.). The ID links to that test's detail section when one exists; a test with no screenshots and nothing failed renders no section, so it is listed as plain text.
- **Step gallery** — for tests with screenshots or failures, a horizontal row of step thumbnails. Each card carries its step number, duration, the action it captured, and a verify tally (`✓2/2`) when the step asserted anything. Detail sections are ordered failures first, then review, then passes — the table keeps run order, the details lead with what went wrong. In practice `sipi run-test` / `run-suite` never mark a step for review, so the middle tier is empty for binary-produced runs (see the note under Badge / status).
- **Step detail** — for failed steps only: the action, each verify check (found / not-found), `failure-type`, and `attempted-methods`. A passing step, review-flagged or not, carries what it has on its card.
- **describe-ui snapshot** — a collapsible block with the first 50 lines of the `describe-ui-snapshot` field (the after-step describe-ui JSON) captured at the point of failure.
- **Lightbox** — clicking a screenshot opens it large with a caption naming the test, step, and action. The arrow keys walk the rest of that test's steps; Esc or a click closes it.

Screenshots are downscaled to 600px on the long side before embedding. That bounds the long side, so a portrait phone capture lands at 276x600 — a little short of 2x for a 200px thumbnail — in exchange for a report that stays a couple of MB instead of 17. A capture whose re-encode would come out no smaller is embedded unchanged, so the 600px figure is a target rather than a guarantee. The report follows the reader's light/dark colour scheme, with a toggle in the header that overrides it. The choice is stored in `localStorage`, which browsers scope per origin — for a `file:` document that is browser-dependent, so it may or may not carry to the next report you open, and a browser that refuses storage entirely just leaves the toggle working per page.

## summary.json

`summary.json` is for tools and agents that need the run result without scraping HTML. It includes:

- `status`: `pass`, `fail`, `review`, or `empty`
- `run-id`, `started`, `finished`
- `device`: name, runtime, and UDID
- `counts`: total, passed, failed, review, skipped
- `top-failures`: first failed step per failed test, including missing verify text and screenshot path when available
- `report`: `report.html`

## Badge / status

The PASS / FAIL / REVIEW / SKIP badge mapping is defined by the Status Display
table in `../references/json-reference.md`.

REVIEW is the one badge the binary cannot currently produce: the harness reads a
`review` flag off each step result but never writes one, so `review` is always
false and the run-level `status` is never `review`. Treat the REVIEW row as
reserved rather than reachable until a step actually sets it.
