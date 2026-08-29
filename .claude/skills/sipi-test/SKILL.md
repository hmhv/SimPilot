---
name: sipi-test
description: Regression testing and quality audits on the iOS Simulator. Creates and runs saved JSON tests for UI flows, reversible file fixtures, persisted app/App Group state, logs and crash evidence, error states, permissions, deep links, push notifications, location, accessibility, appearance, and localization. Use for requests such as "seed the Inbox and test the import", "verify what the app saved", "run the regression suite", "test the network error UI", "deny Photos access", "audit accessibility", "check dark mode", or "verify the Japanese localization". Use sipi-common for one-off data/container operations and sipi-verify for a one-off post-change visual check.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

# iOS Simulator UI Test Automation

Write explicit v2 JSON specs, then hand execution to `sipi run-test` /
`sipi run-suite`.

## Who owns what

**The harness owns** the step loop, target resolution, retry policy, conditional
waits, screenshot and describe-ui capture, verify evaluation, `result.json`,
`trace.jsonl`, `summary.json`, reversible file fixtures,
primary app data-container snapshots/diffs, unified logs, and crash evidence.
Do not reconstruct any of it with Bash. If fixture restoration fails, use only
the explicit `sipi` recovery commands in `docs/run.md`; that is recovery from a
recorded manifest, not a replacement harness.

**You own** intent, the spec, the choice of targets, verify semantics and their
negative controls, fixture selection, evidence interpretation, failure
diagnosis, and source-fix proposals.

## Core Principles

Tests are built from facts observed on the simulator, not from reading source.

- Build specs from operations that actually succeeded on the real screen.
  Reading source and adding `.accessibilityIdentifier()` are tools to stabilize
  real-screen verification, not substitutes for it (`docs/create.md`).
- Judge whether UI state is *meaningfully* correct for the action taken, not
  merely "visible". Expose weaknesses; do not force a PASS (`docs/run.md`).
- When the root cause is in app code, apply the smallest useful change per
  `references/test-fix-policy.md`.
- Use real simulator controls for permissions, links, pushes, location,
  appearance, and network conditions (`references/adverse-state-testing.md`).
- **A test's value is not "it passes" but "its result can be trusted on
  re-run."** A FAIL that catches a regression beats a forced PASS that hides one.

## Run Integrity (hard rules)

1. **RUN and FIX are separate phases.** During a RUN, do not edit test steps,
   verify strings, `config.json`, or app source. A failed verify is a FAIL.
   Fixes happen later, in an explicit FIX phase.
2. **A retry re-executes the same action against the SAME verify object.**
   Changing `action` or `verify` mid-run is a FIX, not a retry. The harness skips
   a retry that would repeat an unconfirmable side effect — text sent but not
   readable back is the case in hand — and records why in the step's `note`.
3. **A verify must assert a state that is ABSENT on the failure path.** Before
   trusting a PASS, confirm the `verify` text would not also appear if the
   feature were broken.

## Workflow

1. Complete `../sipi-common/docs/preflight.md`.
2. Create or update the spec — `docs/create.md`. Summary: understand the
   requirement → observe the simulator with `sipi describe-ui` and screenshots →
   write explicit v2 JSON → `sipi validate .simpilot`. Key names must match
   `references/json-reference.md` exactly; do not invent your own.
3. Run it — `docs/run.md`:

```bash
sipi run-test .simpilot/tests/<id>.json --workspace .simpilot
sipi run-suite .simpilot/suites/<name>.json --workspace .simpilot
```

4. Read `"$RUN_DIR/summary.json"` for the result, and each failing test's
   `<test-id>/result.json` for its steps. Gate on the CLI exit code too.
   Screenshots sit in `<test-id>/step-NNN.png`; `summary.json` `top-failures`
   names the one for each failure. Pass `--html` when a person wants to look
   through the run in a browser, or run `sipi report "$RUN_DIR"` afterwards.

If asked to "create and run", proceed without waiting for confirmation.

## Quality Audits

Beyond functional regression, three audit modes each have their own workflow and
fix priority:

| Mode | Doc | Use when |
|------|-----|----------|
| Accessibility | `docs/a11y-audit.md` | Labels, reading order, identifiers, touch targets, contrast. `sipi a11y-audit` decides the mechanical rules; you judge the rest |
| Appearance | `docs/appearance-check.md` | Dark Mode, Dynamic Type, accessibility-appearance regressions |
| Localization | `docs/l10n-check.md` | Translations, clipped text, locale switching |

Read the relevant doc before starting.

## References

| File | When |
|------|------|
| `../sipi-common/docs/preflight.md` | Every session, before anything else |
| `references/json-reference.md` | Authoring any spec — file, step, selector, verify schema |
| `references/actions.md` | The JSON shape and constraints of a specific action |
| `docs/create.md` | Creating or updating tests |
| `docs/run.md` | Running the harness; flags and semantics |
| `docs/report.md` | Regenerating or reading the HTML report |
| `references/test-fix-policy.md` | **Before proposing or applying any source change** |
| `references/adverse-state-testing.md` | Network errors, permissions, deep links, push, location, system state |
| `references/a11y-best-practices.md` | Accessibility fixes |
| `references/appearance-fix-policy.md` | Appearance / Dark Mode fixes |
| `references/l10n-fix-policy.md` | Localization fixes |
| `../sipi-common/docs/build.md` | Building or installing |
| `../sipi-common/docs/troubleshooting.md` | Any failure |
