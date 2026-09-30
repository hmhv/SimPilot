---
name: sipi-verify
description: Verify feature implementations and bug fixes on the iOS Simulator, capturing iPhone and iPad in light and dark by default. Use after implementing or fixing something to confirm it works correctly and looks right. Use for "verify this works", "check on simulator", "does this look right", "confirm the fix", "check it on the device", "build and run it", "see if it works", "show me how it looks", etc. Also trigger when the user finishes implementing something and wants visual confirmation — even if they don't say "verify" explicitly. This is a one-off, exploratory check of a just-made change (no saved test); to build a repeatable regression test or audit suite, use sipi-test instead.
allowed-tools: Bash, Read, Write, Glob, Grep
model: sonnet
---

# Implementation Verification on iOS Simulator

Confirm a feature or fix on the iOS Simulator, capturing 4 variants by default:
iPhone light, iPhone dark, iPad light, iPad dark.

## Who owns what

**`sipi verify-session` owns** the artifact layout, screenshot naming, variant
alignment, `checks.json`, `findings.json`, and the HTML report. Do not hand-build
any of them. **You own** what to check, the judgment calls, and the findings.

**This skill observes and reports — do not patch product source.** `Edit` is
deliberately absent, but `Write` and `Bash` can still change anything, so the
discipline is yours. Use `Write` for session artifacts only. A code-level
problem is a finding; the fix belongs to `sipi-test`.

## Core Principles

- **Check what matters** — the behavior that was changed, not everything; the
  happy path and the obvious edge cases.
- **Be honest** — if something looks wrong, say so plainly, even when
  `describe-ui` says it is fine.
- **Confirm the new state before declaring all-OK** — before leaving
  `findings.json` empty, confirm through `describe-ui` (not the screenshot alone)
  that you observed the NEW state of the changed behavior, and can say why it
  would be absent had the change not worked. Appearance checks stay
  screenshot-first.
- **4 variants by default** — drop a device class only when it is clearly
  inapplicable (an iPhone-only or iPad-only app, or a change that cannot appear on
  the other class), and say which and why in the answer.
- **Suggest follow-up** — if the check is a good regression candidate, suggest
  `/sipi-test`.

## Fast path — six turns

Wall-clock time goes to model turns, not to the simulator: every `sipi` call
here takes 0.2–1.3s, while every extra turn costs 5–15s. So:

- **Do not read the reference docs up front.** This section is enough for an
  ordinary change. Open a doc only for the situation it covers (table below) —
  a failure, a control that ignores taps, a foldable, video.
- **Batch.** Each turn below is one Bash call (turn 3: one per device, both in
  the same response). Put every command a turn needs into that call.
- **No detours.** `-quiet` plus the exit code is the build verdict — do not
  inspect the binary. The syntax below is complete — no `--help`. Never write a
  `sleep`; wait with `wait-for`.
- **Quote what you fill in.** Inside double quotes the shell still expands `$`
  and backticks, so UI text such as `$9.99` goes in single quotes.

### Turn 1 — context and preflight (one Bash call)

```bash
SIPI="$(command -v sipi || echo "$HOME/.local/bin/sipi")"; printf 'SIPI=%q\n' "$SIPI"
D=$("$SIPI" doctor) && echo "doctor: ok" || echo "doctor: FAILED"; printf '%s\n' "$D" | awk '!/\[ok\]/ || /warning/'
xcrun simctl list devices booted | grep -E 'iPhone|iPad'
cat .simpilot/config.json .simpilot/notes.md 2>/dev/null
git status --short; git log -1 --stat; git show HEAD --format= -- . ':!*.pbxproj' | head -400
```

Point the last line at wherever the change is (`git diff` for uncommitted work).
Read the notes `doctor` prints and act on them before verifying anything — a
binary older than the checkout, an iPhone Duo pose whose screen drops taps. If
`doctor` fails, no iPhone or iPad is booted, or `.simpilot/config.json` is
missing, follow `../sipi-common/docs/preflight.md` before going on. If its
`build` section does not name both `project` and `scheme` (`"build": {}` is
auto-detect mode), or the app is an SPM package, detect them as
`../sipi-common/docs/build.md` describes and save them to `config.json` first.
`notes.md` holds this app's known quirks.

### Turn 2 — build, install, launch, init (one Bash call)

When `config.json` has no `build` key the app is already installed: leave out
`X=`, both `xcodebuild` lines and the `simctl install`, and set `BID` to the
config's `app`. For a workspace use `-workspace`, and when the `build` section
names a `configuration`, add `-configuration <it>` to `X`; see
`../sipi-common/docs/build.md` if the build fails.

```bash
set -e; SIPI=<from turn 1>; IPHONE=<udid>; IPAD=<udid>
X=(-project "<App>.xcodeproj" -scheme "<Scheme>" -destination 'generic/platform=iOS Simulator')
xcodebuild "${X[@]}" 'ARCHS=$(NATIVE_ARCH)' -skipMacroValidation -skipPackagePluginValidation -quiet build
{ read -r APP; read -r BID; } < <(xcodebuild "${X[@]}" -showBuildSettings -json | python3 -c '
import json, sys
for t in json.load(sys.stdin):
    b = t["buildSettings"]
    if b.get("PRODUCT_TYPE") == "com.apple.product-type.application":
        print(b["BUILT_PRODUCTS_DIR"] + "/" + b["FULL_PRODUCT_NAME"]); print(b["PRODUCT_BUNDLE_IDENTIFIER"]); break
else:
    sys.exit("no application target in this scheme")')
PIDS=(); for U in $IPHONE $IPAD; do (xcrun simctl install $U "$APP" && xcrun simctl launch --terminate-running-process $U "$BID" >/dev/null) & PIDS+=($!); done
for PID in "${PIDS[@]}"; do wait "$PID"; done   # a bare `wait` returns 0 even when an install failed
"$SIPI" verify-session init "<kebab-case-summary>"
for U in $IPHONE $IPAD; do "$SIPI" wait-for $U --id "<an id on the app's first screen>" --timeout 15 --interval 0.2 >/dev/null; done
"$SIPI" describe-ui $IPHONE --format compact
```

`init` prints `Verify results: <path>` — that is `VD` from here on; keep it
quoted, since a project path can contain spaces. Wait for
something only this app renders on the screen it opens to (`--id`, `--label` or
`--text`) — the changed screen may be further in — and never for a node count:
SpringBoard answers the first reads after a launch.

### Turn 3 — drive and capture (one Bash call per device, same response)

The two devices are independent, so both chains go in one response. Within a
chain everything is sequential. Plan every check up front, give each an index,
and use the same index and name on both devices so the report grid aligns.

```bash
SIPI=<…>; VD="<…>"; U=<udid>; P=iphone        # the iPad call: its own U, P=ipad
cap() { for M in light dark; do "$SIPI" verify-session capture "$VD" "$P-$M" "$1" --index "$2" --device "$U" --appearance $M >/dev/null; done; }
cap initial-state 1
"$SIPI" tap "$U" --id "<id>"                       # drive the change
"$SIPI" wait-for "$U" --label "<new text>" --timeout 5   # wait for the NEW state
"$SIPI" describe-ui "$U" --format compact | grep -E '<ids of interest>'   # evidence
cap after-action 2
# …one block per check…
"$SIPI" verify-session sheet "$VD" --device $P       # prints the sheet paths to read in turn 4
```

- A static text's content is its **label**: `wait-for --label 3`, not `--value`.
- Taps, text, gestures, alerts, scrolling: `../sipi-common/docs/ui-driver.md`
  and `patterns.md`. The fallback chain there applies when a tap misbehaves.
- A `wait-for` timeout is evidence — the screen never reached the state — and
  worth a finding, not a longer wait.

### Turn 4 — look (every Read in one response)

`sheet` lays a device's captures out as a grid — a row per check (up to three
per sheet), light and dark side by side — so the whole session is a few images.
Read every sheet path the two chains printed, all in a single response. Compare
light against dark and iPhone against iPad: clipped or overlapping text,
unreadable contrast, wrong colors, layout that does not adapt. When a detail is
too small to judge on the sheet, Read that one full-size capture in `VD`, which
is also what the evidence is.

### Turn 5 — record and finalize (one Bash call)

```bash
SIPI=<…>; VD="<…>"
"$SIPI" verify-session finding "$VD" --check <check> --variant <variant> --issue "<what is wrong, and where>"
"$SIPI" verify-session finalize "$VD" --title "<Description>"
cat "$VD/summary.json"
```

One `finding` line per issue; none when everything checked out (the empty
`findings.json` from `init` means All OK). Status is derived from
`findings.json`. Add `--html` to `finalize` only when a person will page through
the screenshots.

### Turn 6 — answer

State the result, each finding, and any skipped variant with the reason. Always
end with the path line — calling skills rely on it:

```
Verify results: <absolute path to VD>
```

## References — open only when the situation applies

| File | When |
|------|------|
| `../sipi-common/docs/preflight.md` | `doctor` fails, nothing booted, no `config.json` |
| `../sipi-common/docs/build.md` | Build fails, workspace/SPM, several app targets |
| `../sipi-common/docs/ui-driver.md` | Driver commands beyond tap / wait-for / describe-ui |
| `../sipi-common/docs/patterns.md` | A control misbehaves; text input, alerts, scrolling |
| `../sipi-common/docs/troubleshooting.md` | Any other failure |
| `docs/verify-workflow.md` | iPhone Duo poses, recording video, measured timings |
| `docs/report.md` | Report layout and the `findings.json` contract |
