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

`--no-launch` is rejected when any selected test has fixtures because safe
fixture installation requires terminating the app before mutation.

Network profiles require a configured provider. Check it before a run that uses `network-condition`:

```bash
sipi network-condition status
```

## Harness Semantics

At run scope, the harness starts filtered unified-log capture unless
`capture-logs` is false. The automatic predicate and crash collection cover the
configured/CLI bundle ID plus every test-level `app` override. An explicit
`log-predicate` replaces that automatic predicate. For each test the harness
then:

1. Terminates the app when fixtures are present, writes recovery metadata, and
   installs each fixture.
2. Captures the primary app data container as `container-before.json` after
   fixture installation unless `capture-container-diff` is false. This does not
   snapshot App Groups or Files.app storage.
3. Launches the app unless `--no-launch` was requested.
4. Runs the deterministic step loop below.
5. Captures that same primary app data container as `container-after.json` and
   `container-diff.json` before restoring fixtures.
6. Terminates the app when fixtures were used and restores every original file.

For each step, the harness:

1. Writes `step-NNN.describe-before.json`.
2. Executes the explicit `action`, if any.
3. Polls until every verify condition holds — including UI text, elements, and
   `container-files` — or the step `wait` timeout expires. Container read errors
   are unmet poll results and never cause the UI action to be replayed.
4. Retries the same action and same verify object up to `--retries` times (extra attempts beyond the first). The count resolves as `--retries`, else `config.json` `max-retries`, else `1`; total attempts = retries + 1, so with the default of `1` a failing step is attempted twice.
5. Writes `step-NNN.describe-after.json`.
6. Captures `step-NNN.png`.
7. Flushes `result.json`.
8. Appends `trace.jsonl`.

`trace.jsonl` is appended live throughout the run (run-start, per-step events,
run-finish). After all tests, the harness normalizes `logs.ndjson`, keeps log
stderr separate, collects exact-bundle-ID crash reports, writes final
`run.json`, then generates `summary.json`. `report.html` is written only when
`--html` is passed, or later by `sipi report <run-dir>`.

Evidence capture is best-effort and does not change a test verdict. Read
`run.json` `evidence-warnings` and the report even when every step passed. An
empty log capture, a partial container snapshot, or failed crash collection is
reported there. Configure `log-predicate` when the app logs under a different
subsystem/process identity.

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

## Results

`summary.json` is the result: `status`, `counts`, and `top-failures` — the first
failed STEP of each test that has one, naming the step, the failure type, the
missing verify, and the screenshot. A test can be marked failed without any step
failing — fixture restoration failing leaves `cleanup-error` on the test and
nothing in `top-failures` — so read `counts` and `status` for the verdict, not
the length of `top-failures`. Read a failing test's `<test-id>/result.json` for
its full step list, and `<test-id>/step-NNN.png` for what the screen looked
like.

`report.html` is not written by default. Pass `--html` to `run-test` /
`run-suite` when a person is going to page through the run in a browser, or
generate it afterwards with `sipi report <run-dir>`. `summary.json` `report`
names the page when it exists and is null when it does not.

Check the **exit code too**, not only `summary.json` `status`. The artifacts are
written before cleanup runs, so an all-green run whose end-of-run restore failed
still reports `"status": "pass"` and signals the problem only by exiting
non-zero. That combination means the tests passed but the simulator was left
dirty — reset before the next run.

A per-test `cleanup-error` means fixture restoration failed. It marks the test
failed but does not by itself make the CLI exit non-zero. Preserve that test's
`fixture-manifest.json` and backup directory and stop using the simulator.
Terminate the affected app, then restore each root represented in the fixture
spec before another run:

```bash
xcrun simctl terminate "$UDID" "$BUNDLE_ID"
sipi container cleanup "$UDID" "$BUNDLE_ID" "$MANIFEST"
sipi container cleanup "$UDID" "$BUNDLE_ID" "$MANIFEST" --group "$GROUP_ID"
sipi files-app cleanup "$UDID" "$MANIFEST" --storage "$STORAGE"
```

Run only the cleanup commands for roots present in the spec. Repeat until the
command reports zero remaining entries. For Files.app, reuse the fixture's
`storage`; if it was omitted and discovery is now ambiguous, use
`sipi files-app candidates` and select the original root rather than guessing.
