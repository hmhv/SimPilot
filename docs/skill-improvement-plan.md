# Skill Improvement Plan

This note analyzes the current SimPilot skills and proposes a more reliable
agent harness, execution loop, and result display model. It is intentionally
implementation-oriented: each recommendation maps to code or skill-doc changes.

## Current Shape

SimPilot currently has three embedded skills:

- `sipi-common`: session setup, driver readiness, config, build/install, recovery
- `sipi-test`: repeatable JSON test creation, execution, quality audits, reports
- `sipi-verify`: exploratory post-change verification with screenshots and
  `findings.json`

The strongest parts of the current design are:

- The skills enforce run integrity: RUN and FIX are separate, retries must use
  the same action and verify string, and strong verifies need a negative control.
- `sipi validate`, `sipi report`, and `sipi verify-report` moved into the binary,
  which makes install and reporting self-contained.
- `describe-ui --expect` gives the agent a cheap default path with a deeper
  fallback when expected text is missing.
- Results are persisted as JSON plus portable self-contained HTML reports.

The main weakness is that the critical execution loop is still mostly in the
LLM's hands. The skill tells the agent to do "1 Bash = 1 step", gather describe
output, choose a target, act, wait, verify, screenshot, record details, and
update hints. That is good guidance, but it leaves too much of the harness to be
reconstructed on every run.

## Recommended Direction

Move from "skills describe the harness" to "skills select a deterministic
harness mode". Keep the skills as thin orchestration manuals, but put the
repeatable loop in `sipi`.

The LLM should remain responsible for:

- Interpreting user intent
- Creating or updating high-level test specs
- Choosing meaningful verifies and negative controls
- Explaining failures and suggesting fixes

The binary should become responsible for:

- Step execution state machine
- Retry policy
- Conditional waits
- Screenshot and `describe-ui` capture timing
- Result JSON construction
- Hint updates
- Structured trace emission
- Report generation

This follows the agent-computer interface lesson from SWE-agent: give the model
task-specific actions and observations instead of making it compose low-level
shell flows repeatedly. It also aligns with current agent platform patterns:
tool calls with strict schemas, durable state after each step, and traceable
agent runs.

## Harness Loop

Add a first-class runner:

```sh
sipi run-test .simpilot/tests/login-flow.json \
  --workspace .simpilot \
  --device <udid> \
  --bundle-id <bundle> \
  --run-dir <dir>
```

And for suites:

```sh
sipi run-suite .simpilot/suites/regression.json \
  --workspace .simpilot \
  --profile .simpilot/devices/regression.json
```

The runner should implement this state machine:

1. Resolve environment: config, app, device, runtime, appearance, orientation,
   commit, build metadata.
2. Launch app and create `run.json` immediately with `started` and pending tests.
3. For each step:
   - Capture `describe-before.json`.
   - Resolve target from `target`, matching hints, and AX tree.
   - Execute action if present.
   - Wait using a polling condition instead of fixed sleep where verify exists.
   - Capture `describe-after.json`.
   - Evaluate verify mechanically.
   - Capture screenshot after verify.
   - Append a result step and flush `result.json` immediately.
4. On failure:
   - Retry the same action and same verify up to `max-retries`.
   - Record `failure-type`, attempted methods, and snapshot.
   - Skip remaining steps unless the step is optional or policy says otherwise.
5. After the test:
   - Apply hint updates only for verified passed steps.
   - Finalize `result.json` and update `run.json`.
6. After the run:
   - Validate the workspace.
   - Generate `report.html`.
   - Generate a machine-readable summary artifact.

The key change is crash resilience: `result.json` and a trace log are flushed
after every logical step. A killed process should leave a partial but valid
result with enough context to resume or diagnose.

## Structured LLM Interface

Introduce strict JSON contracts for model-authored artifacts:

- `test-plan.schema.json`: candidate tests before saving
- `verify-plan.schema.json`: exploratory check matrix for `sipi-verify`
- `fix-suggestion.schema.json`: post-run suggestions only, never run-time edits
- `result-summary.schema.json`: concise final result for chat output

The model should produce these through structured outputs or function/tool
calls, not free-form JSON. Current OpenAI guidance favors Responses API for
reasoning, tool calling, and multi-turn workflows, and Structured Outputs for
schema adherence. The local CLI does not need to depend on OpenAI APIs, but the
skill should be written so Codex/Claude are asked for structured artifacts and
then `sipi validate` gates them.

Recommended model policy for skills:

- Use the strongest available reasoning model for test creation, failure
  diagnosis, and source-fix proposals.
- Use lower-latency model/tool turns for mechanical summarization once the
  runner has emitted structured results.
- Never ask the model to infer pass/fail from screenshots alone for regression
  tests. Use screenshots as evidence, not the oracle.
- For visual verification, require an explicit finding object for each issue and
  an explicit observed-state note before allowing an empty `findings.json`.

## Result Model

Keep the existing `run.json` and `result.json` contract stable, but add optional
artifacts beside them rather than overloading the existing schema.

Proposed new files:

```text
.simpilot/runs/<run-id>/
  run.json
  report.html
  summary.json
  trace.jsonl
  failures.json
  artifacts/
    environment.json
    build.log
  <test-id>/
    result.json
    trace.jsonl
    step-001.png
    step-001.describe-before.json
    step-001.describe-after.json
```

`summary.json` should be optimized for agents and CI:

```json
{
  "status": "fail",
  "run-id": "2026-06-26_104522_iphone16pro_abc1234-dirty",
  "started": "2026-06-26T10:45:22+09:00",
  "finished": "2026-06-26T10:46:12+09:00",
  "device": {
    "name": "iPhone 16 Pro",
    "runtime": "iOS 26.0",
    "udid": "..."
  },
  "counts": {
    "total": 4,
    "passed": 3,
    "failed": 1,
    "review": 0,
    "skipped": 0
  },
  "top-failures": [
    {
      "test": "login-flow",
      "step": 2,
      "failure-type": "verify",
      "action": "Tap Sign In",
      "verify": "Dashboard appears",
      "matched": null,
      "missing": "Dashboard",
      "screenshot": "login-flow/step-002.png"
    }
  ],
  "report": "report.html"
}
```

`trace.jsonl` should be append-only and step-oriented:

```json
{"time":"2026-06-26T10:45:23+09:00","event":"step-start","test":"login-flow","step":1}
{"time":"2026-06-26T10:45:24+09:00","event":"target-resolved","method":"tap-id","value":"auth.sign-in"}
{"time":"2026-06-26T10:45:25+09:00","event":"verify","check":"Dashboard appears","found":false}
```

This gives agents something compact to read before opening the heavy HTML.

## Report Display

The existing HTML report is useful but too static. Improve it in layers:

1. Add an executive strip:
   - Overall status
   - Counts
   - Duration
   - Device/runtime
   - Commit/dirty flag
   - First failing test and step
2. Add filters:
   - Status: FAIL, REVIEW, PASS, SKIP
   - Failure type: action, verify, timeout
   - Test tag
3. Add failure-first layout:
   - Show failed steps before the full screenshot gallery.
   - Include missing verify text, actual grep match if any, attempted methods,
     and collapsed before/after describe snapshots.
4. Add visual diffs for before/after screenshot pairs:
   - Toggle between before, after, and difference.
   - Keep this optional so normal regression reports stay small.
5. Add copyable commands:
   - Re-run this test
   - Open this screenshot
   - Run `sipi describe-ui` on the same device
6. Add a small `summary.json` link/download section:
   - CI and agents should not scrape HTML.

For `sipi-verify`, improve the grid:

- Show findings above the screenshot matrix.
- Add variant filters.
- Mark cells referenced by `findings.json`.
- Add per-cell captions from a structured `checks.json`, not only filenames.
- Add "missing screenshot" diagnostics when a row is incomplete.

## Skill Document Changes

Implemented direction:

- `sipi-test/SKILL.md` should say: create or update specs, then call
  `sipi run-test` or `sipi run-suite`. It should no longer require the agent to
  manually execute each step with Bash.
- `sipi-test/docs/run.md` should become runner semantics and troubleshooting,
  not a shell recipe.
- `sipi-verify/docs/verify-workflow.md` calls `sipi verify-session` for variant
  setup, screenshot naming, findings, and report assembly, while leaving
  exploratory judgment to the model.
- `sipi-common/docs/ui-driver.md` remains available for ad-hoc driving, but it is
  no longer the test execution harness.

This reduces token load and prevents agents from accidentally drifting away from
the intended loop.

## Implementation Plan

### Phase 1: Result Display and Agent Summary

Low risk, high value. The first slice of this phase is implemented: `sipi
report` now emits `summary.json`, test reports show failure highlights before
the table, and verify reports show findings before the screenshot grid.

- Add `summary.json` generation to `sipi report`.
- Add failure-first sections to `ReportGenerator.testReportHTML`.
- Add findings-first sections to `verifyReportHTML`.
- Add tests for summary generation and HTML failure rendering.

### Phase 2: Trace Files

Implemented for `run-test` / `run-suite`: append-only `trace.jsonl` is written
at the run and per-test level.

- Define `TraceEvent` in `SimCore`.
- Add helpers for ISO 8601 timestamps with timezone offset.
- Emit trace events from future runner code and from report/verify generators
  when possible.
- Teach reports to link/show trace snippets for failures.

### Phase 3: Native Runner

Implemented first cut: the step loop moved into `sipi run-test` and
`sipi run-suite`.

- Add typed models for config, tests, suites, device profiles, results.
- Add `run-test` first, then `run-suite`.
- Reuse `NativeDriver`, `AccessibilityPoller`, and target resolution logic.
- The old natural-language test-step format is intentionally replaced by v2
  explicit action/verify objects.

### Phase 4: Verify Session Harness

Implemented first cut: `sipi verify-session init/capture/finding/finalize`.

- Add `verify-session init`, `capture`, `finding`, and `finalize`.
- Generate `checks.json` and `findings.json`.
- Capture variants consistently.
- Produce a report that maps findings to grid cells.

### Phase 5: Skill Rewrite

Implemented first cut: core `sipi-test` and `sipi-verify` docs now point to the
new commands.

- Keep hard integrity rules in SKILL.md.
- Move edge-case details to references.
- Replace shell-loop recipes with `sipi` command contracts.
- Add examples that show result paths and structured summary usage.

## Open Design Questions

- Should `run-test` accept natural-language steps and resolve them internally?
  Decision: no. v2 specs use explicit action/verify objects so the harness stays
  deterministic.
- Should visual checks be model-scored? Recommendation: not for regression
  pass/fail. Use model vision only for exploratory `sipi-verify` findings, and
  preserve human-reviewable screenshots.
- Should reports become a local web app? Recommendation: not initially. Keep
  self-contained HTML for portability, add enough JS for filtering and lightbox.
- Should the runner support resume? Recommendation: yes after trace files exist.
  Start with "resume from first missing/failed pending step" and mark resumed
  runs explicitly in `summary.json`.

## External References

- OpenAI Structured Outputs: https://developers.openai.com/api/docs/guides/structured-outputs
- OpenAI reasoning models and Responses API: https://developers.openai.com/api/docs/guides/reasoning
- OpenAI function calling flow: https://developers.openai.com/api/docs/guides/function-calling
- OpenAI Agents SDK tracing: https://openai.github.io/openai-agents-python/tracing/
- LangGraph durable execution / human-in-the-loop overview: https://docs.langchain.com/oss/python/langgraph/overview
- SWE-agent paper on agent-computer interfaces: https://arxiv.org/abs/2405.15793
