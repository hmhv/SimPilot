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

## findings.json contract

`findings.json` lives in the verify directory and drives the report status badge:

- **Empty array `[]`** → "All OK" (status `status-ok`) — no issues found in any variant
- **Non-empty array** → "Issues Found" (status `status-issue`) — at least one check has an issue
- Missing file + `--status ok` → warning (status caller-asserted without verification)
- Missing file + no flag → defaults to "Issues Found" (fail-safe)

Each issue is an object, e.g. `{ "check": "toggle-on", "variant": "ipad-dark", "issue": "toggle label clipped" }`. Do not add other top-level keys.

## HTML Report Generation

`sipi verify-report` is the sole generator for `report.html`:

```bash
sipi verify-report "$VERIFY_DIR" --title "Description"
open "$VERIFY_DIR/report.html"
```

It reads the screenshots from each variant directory and the status from `findings.json`, then writes a self-contained single HTML file. Images are embedded as **Base64 data URIs** (not relative-path image files), so the report is a portable, standalone file: variants are laid out as columns and checks as rows, with a caption per row. Do not build the HTML by hand — there is no template to fill in or N/A placeholder to insert; missing screenshots are handled by the generator.
