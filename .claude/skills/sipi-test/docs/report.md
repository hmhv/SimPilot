# HTML Report Generation

After all tests complete and `sipi validate .simpilot` shows OK, generate the report with the sole supported generator:

```bash
sipi report "$RUN_DIR"
open "$RUN_DIR/report.html"
```

`sipi report` reads `run.json` and each `result.json` and writes a single self-contained `report.html`. There is no manual/by-hand path — do not assemble the HTML yourself.

## What the report contains

`report.html` is self-contained: all screenshots are embedded as **Base64 data URIs**, so the single file is portable on its own (it does not reference image files by relative path). Its logical structure:

- **Run header** — suite name (or "Ad-hoc Run"), start time, device name + runtime + commit, total duration, and a summary bar of pass/fail/review counts.
- **Results table** — one row per test: status badge, test ID, duration, and notes (coordinate fallback, retries, etc.).
- **Step gallery** — for tests with screenshots or failures, a horizontal row of step thumbnails, each marked with its step number and pass/fail/review state.
- **Step detail** — for failed or review steps: the action, each verify check (found / not-found), `failure-type`, and `attempted-methods`.
- **describe-ui snapshot** — a collapsible block with the first 50 lines of `ui_describe` captured at the point of failure.
- **Lightbox** — clicking any screenshot opens it full-size; Esc or click closes it.

## Badge / status

The PASS / FAIL / REVIEW / SKIP badge mapping is defined by the Status Display table in `../references/json-reference.md`.
