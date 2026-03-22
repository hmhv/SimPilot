# Report Output

## Directory Structure

```
.simpilot/verify/<timestamp>_<description>/
  iphone-light/
    001_<check-name>.png
    002_<check-name>.png
  iphone-dark/
    001_<check-name>.png
    002_<check-name>.png
  ipad-light/
    001_<check-name>.png
    002_<check-name>.png
  ipad-dark/
    001_<check-name>.png
    002_<check-name>.png
  findings.json
  report.html
```

### Directory naming

- Timestamp: `YYYY-MM-DD_HHmmss`
- Description: kebab-case summary of the implementation (e.g., `add-settings-toggle`, `fix-navigation-crash`)
- Example: `2026-03-21_143022_add-settings-toggle`

### Screenshot naming

- Zero-padded 3-digit number + kebab-case description: `001_settings-screen.png`
- Same number and name across all 4 variant directories
- Extra screenshots discovered during exploration use the next available number

## Creating the Output Directory

```bash
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
DESCRIPTION="<kebab-case-summary>"
VERIFY_DIR=".simpilot/verify/${TIMESTAMP}_${DESCRIPTION}"
mkdir -p "$VERIFY_DIR"/{iphone-light,iphone-dark,ipad-light,ipad-dark}
```

## HTML Report Generation

After all screenshots are captured, generate `report.html` in the verify directory.

### Requirements

- Self-contained single HTML file (inline CSS, no external dependencies)
- Images referenced by relative path (so the directory is portable)
- Grid layout: variants as columns, checks as rows
- Each row has a caption describing the check
- Responsive — works in any browser window size

### Template

Generate the HTML with this structure. Replace `{{TITLE}}`, `{{TIMESTAMP}}`, and the check rows dynamically.

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Verify: {{TITLE}}</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; background: #f5f5f7; color: #1d1d1f; padding: 24px; }
  h1 { font-size: 24px; font-weight: 600; margin-bottom: 4px; }
  .meta { color: #86868b; font-size: 14px; margin-bottom: 24px; }
  .status { display: inline-block; padding: 2px 10px; border-radius: 12px; font-size: 13px; font-weight: 500; margin-left: 8px; }
  .status-ok { background: #d4edda; color: #155724; }
  .status-issue { background: #f8d7da; color: #721c24; }
  table { width: 100%; border-collapse: collapse; background: #fff; border-radius: 12px; overflow: hidden; box-shadow: 0 1px 3px rgba(0,0,0,0.08); }
  thead th { background: #f5f5f7; padding: 12px 8px; font-size: 13px; font-weight: 600; text-align: center; border-bottom: 1px solid #e5e5e5; }
  thead th:first-child { text-align: left; padding-left: 16px; }
  tbody td { padding: 8px; vertical-align: top; border-bottom: 1px solid #f0f0f0; }
  tbody td:first-child { font-size: 14px; font-weight: 500; padding-left: 16px; min-width: 160px; }
  tbody td img { width: 100%; border-radius: 8px; cursor: pointer; transition: transform 0.2s; }
  tbody td img:hover { transform: scale(1.02); }
  /* Lightbox */
  .lightbox { display: none; position: fixed; inset: 0; background: rgba(0,0,0,0.85); z-index: 100; justify-content: center; align-items: center; cursor: zoom-out; }
  .lightbox.active { display: flex; }
  .lightbox img { max-width: 90vw; max-height: 90vh; border-radius: 8px; }
</style>
</head>
<body>

<h1>{{TITLE}} <span class="status {{STATUS_CLASS}}">{{STATUS_LABEL}}</span></h1>
<p class="meta">{{TIMESTAMP}}</p>

<table>
  <thead>
    <tr>
      <th>Check</th>
      <th>iPhone Light</th>
      <th>iPhone Dark</th>
      <th>iPad Light</th>
      <th>iPad Dark</th>
    </tr>
  </thead>
  <tbody>
    <!-- Repeat for each check item -->
    <tr>
      <td>
        {{CHECK_DESCRIPTION}}
        <!-- If issue found: -->
        <div class="issue-note">{{ISSUE_NOTE}}</div>
        <!-- If note: -->
        <div class="note">{{NOTE}}</div>
      </td>
      <td><img src="iphone-light/{{FILENAME}}" alt="iPhone Light" onclick="openLightbox(this)"></td>
      <td><img src="iphone-dark/{{FILENAME}}" alt="iPhone Dark" onclick="openLightbox(this)"></td>
      <td><img src="ipad-light/{{FILENAME}}" alt="iPad Light" onclick="openLightbox(this)"></td>
      <td><img src="ipad-dark/{{FILENAME}}" alt="iPad Dark" onclick="openLightbox(this)"></td>
    </tr>
    <!-- End repeat -->
  </tbody>
</table>

<div class="lightbox" id="lightbox" onclick="closeLightbox()">
  <img id="lightbox-img" src="" alt="">
</div>

<script>
function openLightbox(el) {
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

### Status values

- `status-ok` / `All OK` — no issues found in any variant
- `status-issue` / `Issues Found` — at least one check has an issue

### Generating the HTML

Build the HTML using the bundled Swift script, or manually in a Bash heredoc. For each check item, emit one `<tr>` row with:

1. The check description (and issue note if applicable)
2. Four `<img>` tags pointing to the corresponding screenshot in each variant directory

If a screenshot is missing for a variant (e.g., iPad couldn't reach a screen), use a placeholder `<td>` with text "N/A".

### Opening the report

```bash
open "$VERIFY_DIR/report.html"
```
