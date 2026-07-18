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
  checks.json
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
sipi verify-session init "<kebab-case-summary>"
```

## findings.json contract

`findings.json` lives in the verify directory and drives the report status badge. Create it with `sipi verify-session init`; add issues with `sipi verify-session finding`.

- **Empty array `[]`** → "All OK" (status `status-ok`) — no issues found in any variant
- **Non-empty array** → "Issues Found" (status `status-issue`) — at least one check has an issue
- **Missing or invalid file** → status stays fail-safe "Issues Found"

`sipi verify-session finalize` never asserts a status — it always derives it from `findings.json` (empty `[]` → All OK, non-empty → Issues Found). The `--status` override exists only on the standalone `sipi verify-report` command (which this skill does not use in the normal flow), and it is honored **only when `findings.json` is absent**. Whenever `findings.json` exists — the normal case, since `init` writes `[]` — it is authoritative and a conflicting `--status` is ignored with a stderr warning.

Each issue is an object, e.g. `{ "check": "toggle-on", "variant": "ipad-dark", "issue": "toggle label clipped" }`. Do not add other top-level keys.

## HTML Report Generation

`sipi verify-session finalize` is the supported finalizer for `report.html`:

```bash
sipi verify-session finalize "$VERIFY_DIR" --title "Description"
open "$VERIFY_DIR/report.html"
```

It reads the screenshots from each variant directory and the status from `findings.json`, then writes a self-contained single HTML file. Images are embedded as **Base64 data URIs** (not relative-path image files), so the report is a portable, standalone file.

To regenerate `report.html` for an existing verify directory without re-finalizing, use the standalone command `sipi verify-report "$VERIFY_DIR" --title "Description"`. It produces the same HTML and prints only `Report generated: <path>` (not finalize's extra `Verify results:` line).

The report shows `findings.json` first, before the screenshot grid:

- Empty findings render as "No findings recorded."
- Non-empty findings render each issue with check, variant, and issue text.
- Missing or invalid `findings.json` is called out explicitly and the status remains fail-safe.

Variants are laid out as columns and checks as rows, with a caption per row. Do not build the HTML by hand — there is no template to fill in or N/A placeholder to insert; missing screenshots are handled by the generator.
