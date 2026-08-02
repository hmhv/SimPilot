---
name: sipi-verify
description: Verify feature implementations and bug fixes on the iOS Simulator, capturing iPhone and iPad in light and dark by default. Use after implementing or fixing something to confirm it works correctly and looks right. Use for "verify this works", "check on simulator", "does this look right", "confirm the fix", "check it on the device", "build and run it", "see if it works", "show me how it looks", etc. Also trigger when the user finishes implementing something and wants visual confirmation — even if they don't say "verify" explicitly. This is a one-off, exploratory check of a just-made change (no saved test); to build a repeatable regression test or audit suite, use sipi-test instead.
allowed-tools: Bash, Read, Write, Glob, Grep
---

# Implementation Verification on iOS Simulator

Confirm a feature or fix on the iOS Simulator, capturing 4 variants by default:
iPhone light, iPhone dark, iPad light, iPad dark.

## Who owns what

**`sipi verify-session` owns** the artifact layout, screenshot naming, variant
alignment, `checks.json`, `findings.json`, and the HTML report. Do not hand-build
any of them.

**You own** what to check, the judgment calls, and the findings.

**This skill observes and reports — do not patch product source.** That is a
behavioral rule, not something the tool list enforces: `Edit` is deliberately
absent, but `Write` can still overwrite a file and `Bash` can change anything, so
the discipline is yours. Use `Write` for session artifacts only. When
verification surfaces a code-level problem, record it as a finding and hand the
fix to `sipi-test`, which owns source changes.

## When this skill is used

- After a new feature → verify it works as intended
- After a bug fix → verify the issue is resolved
- After UI changes → verify the appearance is correct
- "Check this on the simulator", "verify this works", "does this look right"

## Core Principles

- **Understand first** — read the change to know what to check.
- **Check what matters** — the behavior that was changed, not everything.
- **Be honest** — if something looks wrong, say so plainly.
- **Show evidence** — `sipi screenshot` captures and `sipi describe-ui` output.
- **Confirm the new state before declaring all-OK** — before leaving
  `findings.json` empty, confirm you observed the NEW state for the specific
  changed behavior via `describe-ui` (not the screenshot alone), and can say why
  that state would be absent if the change had not worked. Appearance checks stay
  screenshot-first and exploratory.
- **4 variants by default** — drop a device class only when it is clearly
  inapplicable (an iPhone-only or iPad-only app, or a change that cannot appear
  on the other class). State any skipped variant and why in the summary.
- **Suggest follow-up** — if the check is a good regression candidate, suggest
  `/sipi-test`.

## Approach

Exploratory, not scripted. Unlike regression tests: no predefined JSON steps;
screenshots are first-class evidence; flag anything that looks off even when
`describe-ui` says it is fine; cover the happy path and the obvious edge cases.

## Workflow

Full procedure in `docs/verify-workflow.md`:

1. Complete `../sipi-common/docs/preflight.md`.
2. **Understand the change** — read the diff or context.
3. **Plan checks** — behavior, appearance, edge cases.
4. **Build & install** — rebuild if source changed; install on both devices.
5. **Execute** — the same checks across all 4 variants.
6. **Record findings** — `sipi verify-session finding` for every issue.
7. **Finalize** — `sipi verify-session finalize`.

Use the element-interaction fallback chain in
`../sipi-common/docs/patterns.md` when a tap misbehaves.

## Output

Screenshots, `checks.json`, `findings.json`, and a self-contained HTML report
land in `.simpilot/verify/<timestamp>_<description>/`.

```bash
sipi verify-session finalize "$VERIFY_DIR" --title "Description"
```

`finalize` is the only finalizer this skill uses and it has no status flag —
status is derived from `findings.json` (empty `[]` → All OK, any finding →
Issues Found). To assert an OK result, record an empty findings array. See
`docs/report.md` for the directory layout, naming rules, and the `findings.json`
contract.

### Returning results to the caller

**Always** output the result path. Calling skills rely on this line to locate the
screenshots and report:

```
Verify results: <absolute path to $VERIFY_DIR>
```

## References

| File | When |
|------|------|
| `../sipi-common/docs/preflight.md` | Every session, before anything else |
| `docs/verify-workflow.md` | Before starting verification |
| `docs/report.md` | Report layout and the `findings.json` contract |
| `../sipi-common/docs/ui-driver.md` | Driver commands |
| `../sipi-common/docs/patterns.md` | Element interaction and control quirks |
| `../sipi-common/docs/build.md` | Building or installing |
| `../sipi-common/docs/troubleshooting.md` | Any failure |
