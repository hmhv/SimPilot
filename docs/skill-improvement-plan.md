# Skill Design Notes

Why the SimPilot skills are shaped the way they are, which decisions are settled,
and what is still open. The original plan document described work that has since
been built; this is what survives of it.

## The three skills

- `sipi-common` — session setup, driver readiness, config, build/install,
  recovery, ad-hoc driving
- `sipi-test` — repeatable JSON tests, execution, quality audits, reports
- `sipi-verify` — exploratory post-change verification with screenshots and
  `findings.json`

## Settled: the harness owns the loop

The skills select a deterministic harness mode; they do not describe a harness
for the model to reconstruct. Anything repeatable lives in the binary.

**`sipi` owns** the step execution state machine, retry policy, conditional
waits, screenshot and `describe-ui` capture timing, result JSON, hint updates,
trace emission, and report generation.

**The model owns** interpreting user intent, authoring specs, choosing meaningful
verifies and negative controls, explaining failures, and proposing fixes.

This is the agent-computer-interface lesson from SWE-agent
(<https://arxiv.org/abs/2405.15793>): give the model task-specific actions and
observations instead of making it compose low-level shell flows on every run.

The practical consequence is partial durability. `result.json` and `trace.jsonl`
are flushed after every logical step, so a killed process still leaves the steps
that completed, with enough context to diagnose where it stopped.

It is not yet a *valid* artifact: `sipi validate` compares the result's step
count against the test definition and errors on a truncated run ("result has N
steps but test definition has M"). Nor can it be continued — resume is not
implemented (see Still open). Treat an interrupted run as diagnostic material and
re-run from the start.

## Settled decisions

| Question | Decision |
|---|---|
| Should `run-test` accept natural-language steps? | **No.** v2 specs use explicit action/verify objects so the harness stays deterministic. |
| Should visual checks be model-scored? | **Not for regression pass/fail.** Model vision is for exploratory `sipi-verify` findings only; screenshots stay human-reviewable evidence, never the oracle. |
| Should reports become a local web app? | **No.** Self-contained HTML stays portable; add only enough JS for filtering and the lightbox. |
| Should a step failure ever be repaired mid-run? | **No.** RUN and FIX are separate phases, and the failing run is preserved. |

Artifact layout, `summary.json`, and `trace.jsonl` shapes are specified in
[`json-reference.md`](../.claude/skills/sipi-test/references/json-reference.md),
which is the contract — not this file.

## Still open

Report display, beyond the failure-first and findings-first sections already
shipped:

- filters by status, failure type, and test tag
- before/after screenshot diffs, toggleable so normal reports stay small
- copyable re-run commands per failed test
- verify grid: variant filters, cells marked when referenced by `findings.json`,
  per-cell captions from `checks.json` rather than filenames, and explicit
  "missing screenshot" diagnostics

Runner resume: "resume from the first missing or failed pending step", with
resumed runs marked explicitly in `summary.json`. The trace files it needs now
exist.
