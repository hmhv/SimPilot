---
name: sipi-test
description: Regression testing and quality audits on the iOS Simulator. Handles test creation, execution, suite management, accessibility audit, appearance verification, and localization check. Use for "test", "regression test", "check accessibility", "check dark mode", "check localization", "UI test", "run tests on simulator", "test the app", "create a test", "run the regression suite", etc. Also use when the user asks to audit accessibility, verify translations, or compare light/dark mode — even if they don't mention "test" explicitly.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

# iOS Simulator UI Test Automation

Use AXe CLI to interact with apps on the simulator and manage test creation, execution, and results. All operations go through the Bash tool. See `references/json-reference.md` for JSON format details.

Read `references/test-fix-policy.md` before proposing or applying source-code changes.

## Core Principles

This skill **creates tests based on facts observed and confirmed directly on the simulator**.

- When creating a test, first check the actual screen on the simulator and build steps based on operations that actually succeeded
- Checking source code and adding `.accessibilityIdentifier()` are supplementary tools to help stabilize real-screen verification — not the primary approach
- Judge whether UI state is meaningfully correct for the action taken, not just "visible" or "found by grep". Use a skeptical mindset — expose weaknesses, do not force a PASS
- When the root cause is in app code, propose and apply the smallest useful source change per the Fix Priority below
- After a test is created, do not make ad hoc adjustments during execution to force a PASS — run with the established rules, and mark FAIL if verify does not pass
- **The value of a test is not "making it pass" but "being able to trust results when re-run under the same rules."** A FAIL that correctly catches a regression is more valuable than a forced PASS that hides one

## Mindset When Creating Tests

- Start by checking the current screen with `axe screenshot` / `axe describe-ui`
- Base steps on operations that actually worked
- For elements that are unstable based on the real screen alone, cross-check by reviewing source code
- For elements that repeatedly fall back to coordinate-based interaction, consider adding `.accessibilityIdentifier()`
- System UI and areas where `axe describe-ui` cannot reach should be excluded from regression tests or replaced with pre-seeding

## Mindset When Running Tests

- Do not rewrite existing steps to force a PASS
- Evaluate verify mechanically using `axe describe-ui | grep` — screenshots alone are not sufficient because they are subjective and non-reproducible across runs
- If a hint fails, return to the standard fallback chain — do not invent ad hoc workarounds
- If verify still does not pass, mark FAIL

## Fix Priority

Prefer fixes in this order:

1. add or correct stable identifiers and labels
2. replace fragile custom interactions with standard controls when local and safe
3. add deterministic seed data, debug hooks, or launch paths that improve repeatability
4. adjust layout or timing only when the root cause is clearly in app code

If the fix is local, low-risk, and improves repeatability without masking a real bug, implement it instead of only reporting it.
Do not implement changes whose main effect is hiding a defect or making the test pass without improving the product.

## Preflight

Read `../sipi-common/docs/preflight.md` and complete all checks before proceeding.
Before using AXe, read the `axe` skill (registered as a Claude Code / Codex skill; typically at `~/.claude/skills/axe/SKILL.md` or `~/.agents/skills/axe/SKILL.md`). If the `axe` skill is not available, tell the user that it is required for this workflow and stop rather than improvising AXe usage.

## Element Interaction Fallback Chain

Always check `docs/patterns.md` first — some controls (Toggle, Menu, DisclosureGroup) return "success" from tap but do not actually change state.

```
0. Check docs/patterns.md for the target control
   → If marked "false success", skip to the method that works
1. axe tap --label "Label"
   ↓ fail
2. axe tap --id "identifier"
   ↓ fail
3. axe touch -x N -y N  (from frame: cx=x+w/2, cy=y+h/2)
   ↓ verify fail
4. Visual operation from screenshot:
   a. axe screenshot → Read → determine position/state
   b. Execute action (touch / swipe / long press / clipboard paste)
   c. verify → if fail, mark FAIL
```

## Test Creation

See `docs/create.md` for the full procedure. Summary: understand requirements → build & check screen & review source → generate JSON → save → suggest execution. If asked to "create and run", proceed without waiting for confirmation.

## Test Execution

See `docs/run.md` for the full procedure, build, hint updates, failure recording, and error recovery. Key rules:

- **1 Bash = 1 step** — batching multiple steps loses intermediate screenshots, making it impossible to pinpoint which step failed
- **Continue with `;` on failure, not `&&`** — `&&` aborts the rest of the command, so the post-failure screenshot never gets saved
- **verify uses `axe describe-ui | grep` only** — screenshots are subjective and produce non-reproducible results across different runs and reviewers
- **Do not work hard to force a PASS** — the value of a test is failing when it should fail
- Re-define `UDID` and `BUNDLE_ID` at the top of each Bash call (shell state does not persist between calls)

## Saving and Displaying Results

- Write result.json after each test; write run.json after all tests complete
- **Key names must exactly match `references/json-reference.md`** — do not invent custom key names
- **After saving, always run the validator script and fix issues until it shows `OK`** before generating the report
- Generate `report.html`: `swift "$SKILL_ROOT/scripts/generate_test_report.swift" "$RUN_DIR"`
- Open report: `open "$RUN_DIR/report.html"`

## Quality Audits

Beyond functional regression tests, this skill supports specialized quality audits. Each mode has its own workflow and fix priority documented in a dedicated file.

| Mode | Doc | Use when |
|------|-----|----------|
| Accessibility | `docs/a11y-audit.md` | Auditing labels, reading order, identifiers, contrast |
| Appearance | `docs/appearance-check.md` | Checking Dark Mode, Dynamic Type regressions |
| Localization | `docs/l10n-check.md` | Verifying translations, clipped text, locale switching |

Read the relevant doc before starting an audit.

## Device Selection

1. No specification → use single booted device
2. One device specified → search by model/runtime
3. Multiple devices → run in parallel
4. Device set name → look up `devices/<name>.json`
5. No match found → `xcrun simctl create`

## Suite Execution

Build once → run tests sequentially (progress: `[1/8] app-launch: PASS (5s)`) → display results. When keep-runs is exceeded, delete oldest first.

## References

### Always read

| File | Purpose |
|------|---------|
| `docs/patterns.md` | Control-specific interaction patterns and known quirks |
| `../sipi-common/docs/preflight.md` | Session setup checklist |
| `axe` skill | AXe CLI commands; if unavailable, tell the user and stop |

### Read for specific operations

| File | When |
|------|------|
| `docs/create.md` | Creating or updating tests |
| `docs/run.md` | Running tests, hint updates, failure recording, results |
| `docs/report.md` | HTML report template reference |
| `../sipi-common/docs/build.md` | Building or installing the app |
| `../sipi-common/docs/troubleshooting.md` | When problems occur |

### Read before proposing code changes

| File | When |
|------|------|
| `references/test-fix-policy.md` | Any source-code change for test stability |
| `references/a11y-best-practices.md` | Accessibility fixes |
| `references/appearance-fix-policy.md` | Appearance / Dark Mode fixes |
| `references/l10n-fix-policy.md` | Localization fixes |

### Quality audit workflows

| File | When |
|------|------|
| `docs/a11y-audit.md` | Accessibility audit |
| `docs/appearance-check.md` | Dark Mode / Dynamic Type check |
| `docs/l10n-check.md` | Localization verification |
