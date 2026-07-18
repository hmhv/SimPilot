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

- **Run header** — suite name (or "Ad-hoc Run"), start time, device name + runtime + commit, total duration, and a summary bar of pass/fail/review counts.
- **Failure highlights** — failed steps first, before the full results table, with failure type, missing verify text, and attempted methods.
- **Results table** — one row per test: status badge, test ID, duration, and notes (coordinate fallback, retries, etc.).
- **Step gallery** — for tests with screenshots or failures, a horizontal row of step thumbnails, each marked with its step number and pass/fail/review state.
- **Step detail** — for failed or review steps: the action, each verify check (found / not-found), `failure-type`, and `attempted-methods`.
- **describe-ui snapshot** — a collapsible block with the first 50 lines of the `describe-ui-snapshot` field (the after-step describe-ui JSON) captured at the point of failure.
- **Lightbox** — clicking any screenshot opens it full-size; Esc or click closes it.

## summary.json

`summary.json` is for tools and agents that need the run result without scraping HTML. It includes:

- `status`: `pass`, `fail`, `review`, or `empty`
- `run-id`, `started`, `finished`
- `device`: name, runtime, and UDID
- `counts`: total, passed, failed, review, skipped
- `top-failures`: first failed step per failed test, including missing verify text and screenshot path when available
- `report`: `report.html`

## Badge / status

The PASS / FAIL / REVIEW / SKIP badge mapping is defined by the Status Display table in `../references/json-reference.md`.
