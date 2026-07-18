---
name: sipi-test
description: Regression testing and quality audits on the iOS Simulator. Handles test creation, execution, suite management, accessibility audit, appearance verification, and localization check. Use for "run the regression suite", "create a test for login", "audit accessibility", "check dark mode", "verify the Japanese localization", etc. Also use when the user asks to audit accessibility, verify translations, or compare light/dark mode — even if they don't mention "test" explicitly. This produces repeatable, saved JSON tests/suites you can re-run; for a one-off check right after a code change, use sipi-verify instead.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

# iOS Simulator UI Test Automation

Use SimPilot's deterministic v2 harness. Create explicit JSON specs, then run them with `sipi run-test` or `sipi run-suite`. Do not manually reconstruct the old Bash step loop.

Read `references/test-fix-policy.md` before proposing or applying source-code changes.

## Core Principles

This skill **creates tests based on facts observed and confirmed directly on the simulator**, then hands execution to `sipi` so results can be trusted on re-run.

- Build v2 specs from operations that actually succeeded on the real screen. Checking source code and adding `.accessibilityIdentifier()` are supplementary tools to stabilize real-screen verification — not the primary approach (procedure: `docs/create.md`)
- Judge whether UI state is *meaningfully* correct for the action taken, not just "visible". Use a skeptical mindset — expose weaknesses, do not force a PASS (procedure: `docs/run.md`)
- When the root cause is in app code, propose and apply the smallest useful source change per `references/test-fix-policy.md`
- **The value of a test is not "making it pass" but "being able to trust results when re-run under the same rules."** A FAIL that correctly catches a regression is more valuable than a forced PASS that hides one

## Run Integrity (hard rules)

1. **RUN and FIX are separate phases.** During a RUN, do not edit test steps, verify strings, `config.json`, or app source. If verify fails, accept the harness result as FAIL. Fixes happen later, in an explicit FIX phase (`references/test-fix-policy.md`).
2. **A retry re-executes the same action and re-checks the SAME verify object.** Changing `action` or `verify` mid-run is a FIX, not a retry.
3. **A verify must assert a state that is ABSENT on the failure path** (negative control). Before trusting a PASS, confirm the `verify.contains` text would not also appear if the feature were broken.

## Preflight

Read `../sipi-common/docs/preflight.md` and complete all checks before proceeding.
Confirm the native driver is ready with `sipi doctor` (exit 0). If it fails, report the failing capability and stop.

## Element Interaction Fallback Chain

Use `sipi describe-ui` and screenshots during authoring to discover stable identifiers and text. The harness owns tap resolution, retry, wait, verify, screenshots, result JSON, trace, summary, and report generation.

## Test Creation

See `docs/create.md` for the full procedure. Summary: understand requirements → observe simulator → generate explicit v2 JSON → save → run with `sipi run-test`. If asked to "create and run", proceed without waiting for confirmation.

## Test Execution

See `docs/run.md` for the full procedure. Key command:

```bash
sipi run-test .simpilot/tests/<id>.json --workspace .simpilot
sipi run-suite .simpilot/suites/<name>.json --workspace .simpilot
```

The harness writes `run.json`, per-test `result.json`, `trace.jsonl`, `summary.json`, screenshots, describe snapshots, and `report.html`.

## Saving and Displaying Results

- The harness writes `result.json` incrementally and `run.json` after each test.
- **Key names must exactly match `references/json-reference.md`** — do not invent custom key names.
- After saving specs, run `sipi validate .simpilot` and fix schema issues before executing.
- After execution, open `"$RUN_DIR/report.html"` and inspect `"$RUN_DIR/summary.json"` for a compact result.

## Quality Audits

Beyond functional regression tests, this skill supports specialized quality audits. Each mode has its own workflow and fix priority documented in a dedicated file.

| Mode | Doc | Use when |
|------|-----|----------|
| Accessibility | `docs/a11y-audit.md` | Auditing labels, reading order, identifiers, contrast |
| Appearance | `docs/appearance-check.md` | Checking Dark Mode, Dynamic Type regressions |
| Localization | `docs/l10n-check.md` | Verifying translations, clipped text, locale switching |

Read the relevant doc before starting an audit.

Device selection and suite execution are handled by `sipi run-test` / `sipi run-suite` flags documented in `docs/run.md`.

## References

### Always read

| File | Purpose |
|------|---------|
| `../sipi-common/docs/preflight.md` | Session setup checklist (includes `sipi doctor`) |
| `references/json-reference.md` | v2 JSON schema |

### Read for specific operations

| File | When |
|------|------|
| `docs/create.md` | Creating or updating tests |
| `docs/run.md` | Running tests with the deterministic harness |
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
