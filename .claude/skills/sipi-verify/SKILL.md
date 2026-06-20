---
name: sipi-verify
description: Verify feature implementations and bug fixes on the iOS Simulator, capturing iPhone and iPad in light and dark by default. Use after implementing or fixing something to confirm it works correctly and looks right. Use for "verify this works", "check on simulator", "does this look right", "confirm the fix", "check it on the device", "build and run it", "see if it works", "show me how it looks", etc. Also trigger when the user finishes implementing something and wants visual confirmation — even if they don't say "verify" explicitly. This is a one-off, exploratory check of a just-made change (no saved test); to build a repeatable regression test or audit suite, use sipi-test instead.
allowed-tools: Bash, Read, Write, Glob, Grep
---

# Implementation Verification on iOS Simulator

Verify that a feature implementation or bug fix works correctly by checking it on the iOS Simulator. By default, capture 4 variants: iPhone light, iPhone dark, iPad light, iPad dark. Uses SimPilot's native `sipi` driver for UI interaction.

This skill **observes and reports only — it never patches product source.** It authors `findings.json` with Write and generates the report via Bash (`sipi verify-report`), but does not edit application code. If verification surfaces a code-level problem, describe it in the findings and hand the fix to sipi-test, which owns source changes.

## When This Skill Is Used

- After implementing a new feature → verify it works as intended
- After fixing a bug → verify the fix resolves the issue
- After UI changes → verify the appearance is correct
- When the user says "check this on the simulator", "verify this works", "does this look right"

## Core Principles

- **Understand first, then verify** — read the changes to know what to check
- **Check what matters** — focus on the specific behavior that was changed, not everything
- **Be honest** — if something looks wrong or broken, say so clearly
- **Show evidence** — use `ui_screenshot` captures and `ui_describe` output to support findings
- **Confirm the new state before declaring all-OK** — before writing `findings.json` as an empty `[]`, confirm for the SPECIFIC changed behavior that you observed the NEW state via `ui_describe` (not the screenshot alone), and can state why that state would be absent if the change had not worked. Appearance/visual checks remain screenshot-first and exploratory
- **4 variants by default** — always capture iPhone light, iPhone dark, iPad light, iPad dark. Drop a device class only when it is clearly inapplicable (an iPhone-only or iPad-only app, or a change that cannot appear on the other class). When you skip a variant, state in the summary which variants were skipped and why
- **Suggest follow-up** — if the verification reveals a good regression test candidate, suggest the user run `/sipi-test` to capture this as a regression test

## Preflight

Read `../sipi-common/docs/preflight.md` and complete all checks before proceeding.
Read `../sipi-common/docs/ui-driver.md` and define its shell prelude in every Bash call that inspects or taps UI.
Confirm the native driver is ready with `sipi doctor` (exit 0). If it fails, report the failing capability and stop.

## Workflow

See `docs/verify-workflow.md` for the detailed procedure. Summary:

1. **Understand the change** — read the diff or context provided
2. **Plan checks** — decide what to verify (behavior, appearance, edge cases)
3. **Build & install** — rebuild if source was modified, install on both iPhone and iPad simulators
4. **Execute checks** — run the same checks across 4 variants (iPhone light/dark, iPad light/dark)
5. **Record findings** — write `findings.json` (empty `[]` if no issues; array of objects if issues found)
6. **Generate report** — report status is auto-detected from `findings.json`
7. **Summarize** — output the result path and findings summary

## Output

Screenshots, `findings.json`, and a self-contained HTML report are saved under `.simpilot/verify/<timestamp>_<description>/`. See `docs/report.md` for the directory layout, naming rules, and the `findings.json` contract.

Generate the report with `sipi verify-report "$VERIFY_DIR" --title "Description"` — the sole report generator. Status is auto-detected from `findings.json`; do not pass `--status ok` manually.

### Returning results to the caller

**Always** output the result path so calling skills or the user can locate the artifacts. This line must appear in the conversation output; calling skills rely on it to read the screenshots and HTML report for further review (e.g., comparing against design references):

```
Verify results: <absolute path to $VERIFY_DIR>
```

## Element Interaction

Use the shared element-interaction fallback chain defined in `../sipi-common/docs/patterns.md`. That file also has control-specific guidance and known quirks.

## Verification Approach

This is **exploratory, not scripted**. Unlike regression tests:

- No predefined JSON steps — determine what to check based on the change
- Use judgement — if something looks off visually, flag it even if `ui_describe` says it's fine
- Screenshots are first-class evidence here (unlike regression tests where describe-ui is required)
- Check both the happy path and obvious edge cases
- All 4 variants are always captured for comparison

## References

| File | When to Read |
|------|-------------|
| `docs/verify-workflow.md` | Before starting verification |
| `docs/report.md` | When generating the HTML report |
| `../sipi-common/docs/patterns.md` | When interacting with UI elements (shared fallback chain + control quirks) |
| `../sipi-common/docs/preflight.md` | Before starting any session |
| `../sipi-common/docs/ui-driver.md` | UI driver shell prelude and native bridge wrappers |
| `../sipi-common/docs/build.md` | When building or installing |
| `../sipi-common/docs/troubleshooting.md` | When problems occur |
