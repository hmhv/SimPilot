# Report Output

## Directory layout

```
.simpilot/verify/<timestamp>_<description>/
  iphone-light/   001_<check-name>.png  002_<check-name>.png  …
  iphone-dark/    001_<check-name>.png  002_<check-name>.png  …
  ipad-light/     001_<check-name>.png  002_<check-name>.png  …
  ipad-dark/      001_<check-name>.png  002_<check-name>.png  …
  checks.json
  findings.json
  report.html
```

`sipi verify-session init "<kebab-case-summary>"` creates it.

- Directory name: `YYYY-MM-DD_HHmmss` + kebab-case summary, e.g.
  `2026-03-21_143022_add-settings-toggle`.
- Screenshot name: zero-padded 3-digit index + kebab-case check, e.g.
  `001_settings-screen.png`. The same number and name appear in all four variant
  directories; extra screenshots take the next available number.

## findings.json contract

`findings.json` drives the report's status badge. Create it with `init`; add
issues with `sipi verify-session finding`.

| State | Status |
|---|---|
| Empty array `[]` | "All OK" (`status-ok`) |
| Non-empty array | "Issues Found" (`status-issue`) |
| Missing or invalid | "Issues Found" — fail-safe |

Each issue is an object: `{ "check": "toggle-on", "variant": "ipad-dark", "issue": "toggle label clipped" }`.
Do not add other top-level keys.

`finalize` never asserts a status; it always derives one from `findings.json`.
The `--status` override exists only on the standalone `sipi verify-report`
command, and it is honored only when `findings.json` is absent. Since `init`
writes `[]`, the file normally exists and is authoritative — a conflicting
`--status` is ignored with a stderr warning.

## HTML report

```bash
sipi verify-session finalize "$VERIFY_DIR" --title "Description"
open "$VERIFY_DIR/report.html"
```

`finalize` is the supported finalizer. It reads the screenshots from each variant
directory and the status from `findings.json`, then writes one self-contained
HTML file with images embedded as Base64 data URIs, so the report is portable on
its own.

Layout: findings first, then the screenshot grid — variants as columns, checks as
rows, one caption per row.

- Empty findings render as "No findings recorded."
- Non-empty findings render each issue with check, variant, and issue text.
- A missing or invalid `findings.json` is called out explicitly and the status
  stays fail-safe.

To regenerate the HTML for an existing directory without re-finalizing, use
`sipi verify-report "$VERIFY_DIR" --title "Description"`. It produces the same
HTML and prints only `Report generated: <path>`, without finalize's
`Verify results:` line.

Do not build the HTML by hand — the generator handles missing screenshots.
