---
name: sipi-verify
description: Verify feature implementations and bug fixes on the iOS Simulator. Use after implementing or fixing something to confirm it works correctly and looks right. Use for "verify this works", "check on simulator", "does this look right", "confirm the fix", "check it on the device", "build and run it", "see if it works", "show me how it looks", etc. Also trigger when the user finishes implementing something and wants visual confirmation — even if they don't say "verify" explicitly.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

# Implementation Verification on iOS Simulator

Verify that a feature implementation or bug fix works correctly by checking it on the iOS Simulator. By default, capture 4 variants: iPhone light, iPhone dark, iPad light, iPad dark. Uses AXe CLI plus `sipi-ui` for UI interaction.

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
- **4 variants by default** — always capture iPhone light/dark and iPad light/dark unless the user specifies otherwise (e.g., "just iPhone" or "iPad only"). If only a subset is requested, capture that subset
- **Suggest follow-up** — if the verification reveals a good regression test candidate, suggest `/sipi-test create`

## Preflight

Read `../sipi-common/docs/preflight.md` and complete all checks before proceeding.
Read `../sipi-common/docs/ui-driver.md` and define its shell prelude in every Bash call that inspects or taps UI.
Before using AXe, read the `axe` skill (typically at `~/.claude/skills/axe/SKILL.md` or `~/.agents/skills/axe/SKILL.md`). If the `axe` skill is not available, tell the user that it is required and stop.

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

Screenshots and an HTML report are saved to:

```
.simpilot/verify/<timestamp>_<description>/
  iphone-light/
  iphone-dark/
  ipad-light/
  ipad-dark/
  findings.json
  report.html
```

See `docs/report.md` for output structure and HTML generation details.

Generate the report: `swift "$SKILL_ROOT/scripts/generate_verify_report.swift" "$VERIFY_DIR" --title "Description"` (status is auto-detected from `findings.json`; do not pass `--status ok` manually)

### Returning results to the caller

After generating the report, **always output the result path** so that calling skills or the user can locate and review the artifacts:

```
Verify results: <absolute path to $VERIFY_DIR>
```

This line must appear in the conversation output. Calling skills rely on this path to read screenshots and the HTML report for further review (e.g., comparing against design references).

## Element Interaction

Use the same fallback chain as sipi-test (defined in `../sipi-test/SKILL.md`). See `../sipi-test/docs/patterns.md` for control-specific guidance.

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
| `../sipi-test/docs/patterns.md` | When interacting with UI elements |
| `../sipi-common/docs/preflight.md` | Before starting any session |
| `../sipi-common/docs/ui-driver.md` | UI driver shell prelude and native bridge wrappers |
| `../sipi-common/docs/build.md` | When building or installing |
| `../sipi-common/docs/troubleshooting.md` | When problems occur |
