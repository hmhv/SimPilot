# HTML Report Generation

After all tests complete and JSON is validated, generate `report.html` in the run directory.

## Requirements

- Self-contained single HTML file (inline CSS/JS, no external dependencies)
- Images referenced by relative path (directory is portable)
- Works in any browser window size
- `open "$RUN_DIR/report.html"` to view

## Structure

### Run Header

- Suite name (or "Ad-hoc Run") + start time
- Device name + runtime + commit hash
- Summary bar: pass/fail/review counts with colored indicators
- Duration

### Test Results Table

One row per test:

| Status | Test ID | Duration | Notes |
|--------|---------|----------|-------|
| PASS/FAIL/REVIEW/SKIP badge | test id | seconds | coordinate fallback, retries, etc. |

### Test Details

For each test with screenshots or failures, expand a detail section:

- **Step gallery**: Horizontal row of screenshot thumbnails with step number and status indicator
- **Step detail**: Action, verify checks (found/not-found), failure-type, attempted-methods
- **describe-ui snapshot**: Collapsible `<pre>` block (first 50 lines)

### Screenshot Lightbox

Click any screenshot to view full-size in a lightbox overlay. Esc or click to close.

## Template

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Test Run: {{SUITE_OR_ADHOC}}</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; background: #f5f5f7; color: #1d1d1f; padding: 24px; }
  h1 { font-size: 24px; font-weight: 600; margin-bottom: 4px; }
  .meta { color: #86868b; font-size: 14px; margin-bottom: 16px; }
  .summary { display: flex; gap: 16px; margin-bottom: 24px; flex-wrap: wrap; }
  .summary-item { padding: 8px 16px; border-radius: 10px; font-size: 14px; font-weight: 600; }
  .summary-pass { background: #d4edda; color: #155724; }
  .summary-fail { background: #f8d7da; color: #721c24; }
  .summary-review { background: #fff3cd; color: #856404; }
  .summary-total { background: #e2e3e5; color: #383d41; }
  table { width: 100%; border-collapse: collapse; background: #fff; border-radius: 12px; overflow: hidden; box-shadow: 0 1px 3px rgba(0,0,0,0.08); margin-bottom: 24px; }
  thead th { background: #f5f5f7; padding: 12px 16px; font-size: 13px; font-weight: 600; text-align: left; border-bottom: 1px solid #e5e5e5; }
  tbody td { padding: 10px 16px; border-bottom: 1px solid #f0f0f0; font-size: 14px; vertical-align: middle; }
  tbody tr:hover { background: #fafafa; }
  .badge { display: inline-block; padding: 2px 10px; border-radius: 12px; font-size: 12px; font-weight: 600; }
  .badge-pass { background: #d4edda; color: #155724; }
  .badge-fail { background: #f8d7da; color: #721c24; }
  .badge-review { background: #fff3cd; color: #856404; }
  .badge-skip { background: #e2e3e5; color: #6c757d; }
  .detail { background: #fff; border-radius: 12px; padding: 20px; margin-bottom: 16px; box-shadow: 0 1px 3px rgba(0,0,0,0.08); }
  .detail h3 { font-size: 16px; margin-bottom: 12px; }
  .steps { display: flex; gap: 12px; overflow-x: auto; padding: 8px 0; }
  .step-card { flex: 0 0 180px; border: 1px solid #e5e5e5; border-radius: 10px; overflow: hidden; cursor: pointer; transition: transform 0.15s; }
  .step-card:hover { transform: translateY(-2px); box-shadow: 0 4px 8px rgba(0,0,0,0.1); }
  .step-card.fail { border-color: #dc3545; }
  .step-card.review { border-color: #ffc107; }
  .step-card img { width: 100%; aspect-ratio: 9/19.5; object-fit: cover; background: #f0f0f0; }
  .step-card .step-label { padding: 6px 10px; font-size: 12px; font-weight: 500; display: flex; justify-content: space-between; }
  .step-info { margin-top: 12px; font-size: 13px; line-height: 1.6; }
  .step-info dt { font-weight: 600; color: #86868b; margin-top: 8px; }
  .step-info dd { margin-left: 0; }
  .verify-check { display: flex; gap: 6px; align-items: center; }
  .verify-check .found { color: #28a745; }
  .verify-check .not-found { color: #dc3545; }
  pre { background: #f5f5f7; padding: 12px; border-radius: 8px; font-size: 12px; overflow-x: auto; max-height: 300px; overflow-y: auto; margin-top: 8px; }
  details { margin-top: 8px; }
  details summary { cursor: pointer; font-size: 13px; color: #007aff; }
  .note { font-size: 12px; color: #86868b; }
  /* Lightbox */
  .lightbox { display: none; position: fixed; inset: 0; background: rgba(0,0,0,0.85); z-index: 100; justify-content: center; align-items: center; cursor: zoom-out; }
  .lightbox.active { display: flex; }
  .lightbox img { max-width: 90vw; max-height: 90vh; border-radius: 8px; }
</style>
</head>
<body>

<h1>{{SUITE_OR_ADHOC}}</h1>
<p class="meta">{{DEVICE_NAME}} · {{DEVICE_RUNTIME}} · {{COMMIT}} · {{STARTED}}</p>

<div class="summary">
  <span class="summary-item summary-total">{{TOTAL}} tests</span>
  <span class="summary-item summary-pass">{{PASSED}} passed</span>
  <!-- if review > 0 -->
  <span class="summary-item summary-review">{{REVIEW}} review</span>
  <!-- if failed > 0 -->
  <span class="summary-item summary-fail">{{FAILED}} failed</span>
</div>

<table>
  <thead>
    <tr><th>Status</th><th>Test</th><th>Duration</th><th>Notes</th></tr>
  </thead>
  <tbody>
    <!-- Repeat for each test -->
    <tr>
      <td><span class="badge {{BADGE_CLASS}}">{{STATUS}}</span></td>
      <td>{{TEST_ID}}</td>
      <td>{{DURATION}}s</td>
      <td class="note">{{NOTES}}</td>
    </tr>
    <!-- End repeat -->
  </tbody>
</table>

<!-- For each failed or review test -->
<div class="detail">
  <h3><span class="badge {{BADGE_CLASS}}">{{STATUS}}</span> {{TEST_ID}}</h3>

  <div class="steps">
    <!-- Repeat for each step -->
    <div class="step-card {{STEP_CLASS}}" onclick="openLightbox(this.querySelector('img'))">
      <img src="{{TEST_ID}}/{{SCREENSHOT}}" alt="Step {{N}}">
      <div class="step-label">
        <span>Step {{N}}</span>
        <span>{{STEP_DURATION}}s</span>
      </div>
    </div>
    <!-- End repeat -->
  </div>

  <!-- For each failed step -->
  <div class="step-info">
    <h4>Step {{N}}: {{ACTION}}</h4>
    <dl>
      <dt>Failure Type</dt>
      <dd>{{FAILURE_TYPE}}</dd>
      <dt>Verify</dt>
      <dd>
        <!-- Repeat for each verify check -->
        <div class="verify-check">
          <span class="{{FOUND_CLASS}}">{{FOUND_ICON}}</span>
          {{CHECK}}
        </div>
        <!-- End repeat -->
      </dd>
      <dt>Attempted Methods</dt>
      <dd>{{METHODS}}</dd>
    </dl>
    <details>
      <summary>describe-ui snapshot</summary>
      <pre>{{DESCRIBE_UI_SNAPSHOT}}</pre>
    </details>
  </div>
  <!-- End failed step -->
</div>
<!-- End failed/review test -->

<div class="lightbox" id="lightbox" onclick="closeLightbox()">
  <img id="lightbox-img" src="" alt="">
</div>

<script>
function openLightbox(el) {
  if (!el) return;
  document.getElementById('lightbox-img').src = el.src;
  document.getElementById('lightbox').classList.add('active');
}
function closeLightbox() {
  document.getElementById('lightbox').classList.remove('active');
}
document.addEventListener('keydown', e => { if (e.key === 'Escape') closeLightbox(); });
</script>

</body>
</html>
```

## Generating the HTML

Build the HTML by reading `run.json` and each `result.json` in the run directory. For each test:

1. Read `result.json` to get status, duration, steps
2. Emit a table row with status badge, test ID, duration, notes
3. For failed/review tests, emit a detail section with step gallery and failure info

## Badge Classes

Use the status display mapping from `../references/json-reference.md` (Status Display table) to determine the badge class:

- `badge-pass` → PASS
- `badge-fail` → FAIL
- `badge-review` → REVIEW
- `badge-skip` → SKIP

## Opening the Report

```bash
open "$RUN_DIR/report.html"
```
