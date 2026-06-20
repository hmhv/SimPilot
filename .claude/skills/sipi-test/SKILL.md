---
name: sipi-test
description: Regression testing and quality audits on the iOS Simulator. Handles test creation, execution, suite management, accessibility audit, appearance verification, and localization check. Use for "run the regression suite", "create a test for login", "audit accessibility", "check dark mode", "verify the Japanese localization", etc. Also use when the user asks to audit accessibility, verify translations, or compare light/dark mode — even if they don't mention "test" explicitly. This produces repeatable, saved JSON tests/suites you can re-run; for a one-off check right after a code change, use sipi-verify instead.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

# iOS Simulator UI Test Automation

Use SimPilot's native `sipi` driver (via the `ui-driver.md` shell prelude) to interact with apps on the simulator and manage test creation, execution, and results. All operations go through the Bash tool. See `references/json-reference.md` for JSON format details.

Read `references/test-fix-policy.md` before proposing or applying source-code changes.

## Core Principles

This skill **creates tests based on facts observed and confirmed directly on the simulator**, then runs them under fixed rules so results can be trusted on re-run.

- Build steps from operations that actually succeeded on the real screen. Checking source code and adding `.accessibilityIdentifier()` are supplementary tools to stabilize real-screen verification — not the primary approach (procedure: `docs/create.md`)
- Judge whether UI state is *meaningfully* correct for the action taken, not just "visible" or "found by grep". Use a skeptical mindset — expose weaknesses, do not force a PASS (procedure: `docs/run.md`)
- When the root cause is in app code, propose and apply the smallest useful source change per `references/test-fix-policy.md`
- **The value of a test is not "making it pass" but "being able to trust results when re-run under the same rules."** A FAIL that correctly catches a regression is more valuable than a forced PASS that hides one

## Run Integrity (hard rules)

1. **RUN and FIX are separate phases.** During a RUN, do not edit test steps, verify strings, `config.json`, or app source. If verify fails, record FAIL and stop — never edit to make it pass. Fixes happen later, in an explicit FIX phase (`references/test-fix-policy.md`).
2. **A retry re-executes the same action and re-checks the SAME verify string.** Changing the verify condition or target mid-run is a FIX, not a retry. Exhausting retries with the unchanged verify still failing is a FAIL.
3. **A verify must assert a state that is ABSENT on the failure path** (negative control). Before trusting a PASS, confirm the matched `grep` would NOT also match if the feature were broken (e.g. don't grep static chrome or an always-present tab label).

## Preflight

Read `../sipi-common/docs/preflight.md` and complete all checks before proceeding.
Read `../sipi-common/docs/ui-driver.md` and define its shell prelude in every Bash call that inspects or taps UI.
Confirm the native driver is ready with `sipi doctor` (exit 0). If it fails, report the failing capability and stop.

## Element Interaction Fallback Chain

Use the shared element-interaction fallback chain defined in `../sipi-common/docs/patterns.md`. Read it before tapping or inspecting any UI control — some controls (Toggle, Menu, DisclosureGroup) return "success" from tap but do not actually change state, so a screenshot or tap result alone can look like a fake PASS.

## Test Creation

See `docs/create.md` for the full procedure. Summary: understand requirements → build & check screen & review source → generate JSON → save → suggest execution. If asked to "create and run", proceed without waiting for confirmation.

## Test Execution

See `docs/run.md` for the full procedure, build, hint updates, failure recording, and error recovery. Key rules:

- **1 Bash = 1 step** — batching multiple steps loses intermediate screenshots, making it impossible to pinpoint which step failed
- **Continue with `;` on failure, not `&&`** — `&&` aborts the rest of the command, so the post-failure screenshot never gets saved
- **verify uses `ui_describe | grep` only** — screenshots are subjective and produce non-reproducible results across different runs and reviewers
- **Run is read-only on the spec** — see Run Integrity above; mark FAIL rather than editing to pass
- Re-define `UDID` and `BUNDLE_ID` at the top of each Bash call (shell state does not persist between calls)

## Saving and Displaying Results

- Write result.json after each test; write run.json after all tests complete
- **Key names must exactly match `references/json-reference.md`** — do not invent custom key names
- **After saving, always run `sipi validate .simpilot` and fix issues until it shows `OK`** before generating the report
- Generate `report.html`: `sipi report "$RUN_DIR"`
- Open report: `open "$RUN_DIR/report.html"`

## Quality Audits

Beyond functional regression tests, this skill supports specialized quality audits. Each mode has its own workflow and fix priority documented in a dedicated file.

| Mode | Doc | Use when |
|------|-----|----------|
| Accessibility | `docs/a11y-audit.md` | Auditing labels, reading order, identifiers, contrast |
| Appearance | `docs/appearance-check.md` | Checking Dark Mode, Dynamic Type regressions |
| Localization | `docs/l10n-check.md` | Verifying translations, clipped text, locale switching |

Read the relevant doc before starting an audit.

Device selection and suite execution are detailed in `docs/run.md` ("Device Resolution" and "Suite Execution Details").

## References

### Always read

| File | Purpose |
|------|---------|
| `../sipi-common/docs/preflight.md` | Session setup checklist (includes `sipi doctor`) |
| `../sipi-common/docs/ui-driver.md` | UI driver shell prelude and native bridge wrappers |

### Read for specific operations

| File | When |
|------|------|
| `../sipi-common/docs/patterns.md` | Before tapping or inspecting any UI control (fallback chain, control-specific patterns and known quirks) |
| `docs/create.md` | Creating or updating tests |
| `docs/run.md` | Running tests, hint updates, failure recording, results, device/suite selection |
| `docs/report.md` | Generating the HTML report |
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
