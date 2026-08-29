# Report Output

## Directory layout

```
.simpilot/verify/<timestamp>_<description>/
  iphone-light/   001_<check-name>.png  002_<check-name>.png  …
  iphone-dark/    001_<check-name>.png  002_<check-name>.png  …
  ipad-light/     001_<check-name>.png  002_<check-name>.png  …
  ipad-dark/      001_<check-name>.png  002_<check-name>.png  …
  summary.json
  checks.json
  findings.json
  report.html     # only with `finalize --html`, or `sipi verify-report`
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

## summary.json

```bash
sipi verify-session finalize "$VERIFY_DIR" --title "Description"
```

`finalize` is the supported finalizer. It reads the screenshots from each variant
directory and the status from `findings.json`, and writes `summary.json`:

- `status`: `ok` or `issue`, derived from `findings.json`
- `title`, `verify-id`
- `counts`: checks, findings, variants
- `variants`: the variant directories that actually hold captures — an empty one
  is not listed, because `init` creates all four before anything is photographed
- `findings`: the findings themselves, so a reader needs one file
- `checks`: `"checks.json"`, which names every screenshot file
- `report`: `"report.html"` when that page exists, `null` when it does not

## HTML report

```bash
sipi verify-session finalize "$VERIFY_DIR" --title "Description" --html
open "$VERIFY_DIR/report.html"
```

Not written by default. `--html` produces one self-contained HTML file with
images embedded as Base64 data URIs, so the page is portable on its own. Ask for
it when a person is going to look through the screenshots; `summary.json` is
what an agent reads.

Layout: findings first, then the screenshot grid — one row per check, with the
appearance columns grouped under their device (`iPhone: Light | Dark`,
`iPad: Light | Dark`), so light and dark sit adjacent for the comparison a reader
actually makes. A device with no captures anywhere in the session drops out
instead of rendering a column of N/A.

Clicking a screenshot opens it with a caption naming the check, device, and
appearance. The arrow keys walk the rest of that row. Thumbnails are ~200px — the
grid is for scanning, the lightbox is for looking — and screenshots are
downscaled to 600px on the long side before embedding. That bounds the long side,
so a portrait phone capture lands at 276x600, a little short of 2x for a 200px
cell, in exchange for a 28-capture report of 2.4MB rather than 17MB. A capture
whose re-encode would come out no smaller is embedded unchanged, so 600px is a
target rather than a guarantee.

The report follows the reader's light/dark colour scheme, with a toggle in the
header that overrides it. The choice goes to `localStorage`, whose scope for a
`file:` document is browser-dependent, so whether it carries to the next report is
too; the toggle itself always works on the page in front of you.

- Empty findings render as "No findings recorded."
- Non-empty findings render each issue with check, variant, and issue text.
- A missing or invalid `findings.json` is called out explicitly and the status
  stays fail-safe.

To generate the HTML for an existing directory without re-finalizing, use
`sipi verify-report "$VERIFY_DIR" --title "Description"`. It produces the same
page and prints only `Report generated: <path>`, without finalize's
`Verify results:` line.

Do not build the HTML by hand — the generator handles missing screenshots.
