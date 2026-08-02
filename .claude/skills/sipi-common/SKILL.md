---
name: sipi-common
description: Prepares and repairs an iOS Simulator session for SimPilot's native `sipi` driver and drives it ad-hoc — "tap this on the simulator", "describe the current screen", "take a screenshot", or "the simulator/driver is broken". Use for one-off driving, setup, and recovery; use sipi-test for repeatable saved JSON tests and audits, and sipi-verify for a one-off post-change feature check.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

# Shared SimPilot Setup

Session setup, driver readiness, config, build/install, and recovery — the
foundation `sipi-test` and `sipi-verify` both build on, and the skill to use
directly for ad-hoc driving.

## Who owns what

`sipi` owns the bridge: target resolution, fast→deep tree escalation, gesture
composition, and coordinate bounds checking. You own intent — what to tap, what
counts as the right screen, and when the observed state contradicts the request.

## When to use

- Ad-hoc driving that is neither a regression test (`sipi-test`) nor a feature
  check (`sipi-verify`) — tap something, describe the screen, take a screenshot
- Preparing a repository for SimPilot the first time
- Checking whether the native driver and the simulator are ready
- Creating or fixing `.simpilot/config.json`
- Building and installing the app
- Recovering from a simulator, driver, build, or interaction failure

## Workflow

Every session runs this sequence, ad-hoc or otherwise:

1. Complete `docs/preflight.md`. It is the gate — nothing touches the simulator
   until it passes.
2. Write `.simpilot/config.json` if it is missing or incomplete (detection lives
   in `docs/build.md`).
3. If the config has a `build` section, build and install per `docs/build.md`.
4. Drive with the commands in `docs/ui-driver.md`; `docs/patterns.md` has the
   fallback chain and per-control quirks.
5. On failure, apply the smallest fix in `docs/troubleshooting.md` that restores
   a reliable session.

Prefer observed UI over source: `describe-ui` and screenshots are the source of
truth, and worth re-reading after each meaningful action when behavior is flaky.
Run `sipi --help` for the full command set.

## References

| File | When |
|------|------|
| `docs/preflight.md` | Every session, before anything else |
| `docs/ui-driver.md` | Before the first UI interaction |
| `docs/patterns.md` | Choosing how to hit a control, or when a tap misbehaves |
| `docs/build.md` | Building or installing |
| `docs/troubleshooting.md` | Any failure — the canonical list of known modes |
