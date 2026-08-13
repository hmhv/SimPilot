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

Network profiles require a configured provider. Check it before a run that uses `network-condition`:

```bash
sipi network-condition status
```

## Harness Semantics

For each step, the harness:

1. Writes `step-NNN.describe-before.json`.
2. Executes the explicit `action`, if any.
3. Polls `describe-ui` until every verify condition holds — `contains` present, `absent` gone, `matches` matching, `not-matches` not matching, and every `elements` assertion satisfied — or the step `wait` timeout expires. Any absence-shaped condition forces the deep tree; presence-shaped ones escalate to it only when the fast tree does not already satisfy them.
4. Retries the same action and same verify object up to `--retries` times (extra attempts beyond the first). The count resolves as `--retries`, else `config.json` `max-retries`, else `1`; total attempts = retries + 1, so with the default of `1` a failing step is attempted twice.
5. Writes `step-NNN.describe-after.json`.
6. Captures `step-NNN.png`.
7. Flushes `result.json`.
8. Appends `trace.jsonl`.

`trace.jsonl` is appended live throughout the run (run-start, per-step events, run-finish). After the run completes, the harness writes the final `run.json`, then generates `summary.json` and `report.html`.

The harness also cleans up simulator state it owns, at the end of the run and —
in a suite with `reset-between-tests` enabled (the default) — between tests. A
between-test failure is traced and the run continues, then retried by the strict
end-of-run cleanup.

Cleanup is not uniform. Appearance, content size, Increase Contrast,
`display-state`, and biometric enrollment are **restored** to the value captured
before the first write. Location, status-bar overrides, and active
network conditions are only **cleared**, so a pre-existing value is not put back.
`privacy`, `open-url`, `push`, `launch`, and `terminate` get **no cleanup at
all**. The full tier table, with the `display-state` caveat, is in
`../references/adverse-state-testing.md`.

A spec that uses the third tier must recover on its own — and note that a
recovery step placed at the END of a test never runs when an earlier step failed
(see Failure Rules below). Put the reset at the start of the test that needs a
clean state instead.

## Failure Rules

- A failed verify is a failed run. Do not edit the spec during the run.
- A retry never changes the target or verify strings.
- Remaining steps are marked skipped after the first non-optional failure —
  including cleanup or recovery steps at the end of the test.
- `optional` only skips a `tap` / `double-tap` / `long-press` / `slider` whose
  target is not found in either tree. Every other action runs regardless, an
  ambiguous selector or unreadable tree does not skip but falls through to normal
  execution, and a skipped step does not gate the steps after it — see
  `../references/actions.md`.
- Fixes happen in a separate FIX phase.

## Results Display

Open `report.html` for visual inspection and read `summary.json` for a compact machine-readable result. Failure highlights appear before the full table.

Check the **exit code too**, not only `summary.json` `status`. The artifacts are
written before cleanup runs, so an all-green run whose end-of-run restore failed
still reports `"status": "pass"` and signals the problem only by exiting
non-zero. That combination means the tests passed but the simulator was left
dirty — reset before the next run.
