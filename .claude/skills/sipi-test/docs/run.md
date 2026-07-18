# Test Execution

Run v2 specs through the deterministic harness. Do not manually execute individual steps with Bash.

## Commands

Single test:

```bash
sipi run-test .simpilot/tests/<id>.json --workspace .simpilot
```

Suite:

```bash
sipi run-suite .simpilot/suites/<name>.json --workspace .simpilot
```

Useful flags:

- `--device <udid>`: choose a simulator
- `--bundle-id <id>`: override `.simpilot/config.json` `app`
- `--run-dir <path>`: choose the output directory
- `--retries <n>`: override retry count
- `--no-launch`: run from current app state

## Harness Semantics

For each step, the harness:

1. Writes `step-NNN.describe-before.json`.
2. Executes the explicit `action`, if any.
3. Polls `describe-ui` until `verify.contains` are present and `verify.absent` are absent, or the step `wait` timeout expires.
4. Retries the same action and same verify object up to `--retries` times (extra attempts beyond the first). The count resolves as `--retries`, else `config.json` `max-retries`, else `1`; total attempts = retries + 1, so with the default of `1` a failing step is attempted twice.
5. Writes `step-NNN.describe-after.json`.
6. Captures `step-NNN.png`.
7. Flushes `result.json`.
8. Appends `trace.jsonl`.

`trace.jsonl` is appended live throughout the run (run-start, per-step events, run-finish). After the run completes, the harness writes the final `run.json`, then generates `summary.json` and `report.html`.

## Failure Rules

- A failed verify is a failed run. Do not edit the spec during the run.
- A retry never changes the target or verify strings.
- Remaining steps are marked skipped after the first non-optional failure.
- Fixes happen in a separate FIX phase.

## Results Display

Open `report.html` for visual inspection and read `summary.json` for a compact machine-readable result. Failure highlights appear before the full table.
