---
name: sipi-common
description: Prepares and repairs an iOS Simulator session for SimPilot's native `sipi` driver and drives it ad-hoc — "tap this on the simulator", "describe the current screen", "take a screenshot", or "the simulator/driver is broken". Use for one-off driving, setup, and recovery; use sipi-test for repeatable saved JSON tests and audits, and sipi-verify for a one-off post-change feature check.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

# Shared SimPilot Setup

Use this skill for the common workflow behind `sipi-test` and `sipi-verify`.
It covers session initialization, native driver prerequisites, simulator readiness, `.simpilot/config.json`, build/install, and recovery when the workflow breaks.

## When To Use

- Ad-hoc "just drive the simulator" requests — tap something, describe the current screen, take a screenshot — that are neither a regression test (`sipi-test`) nor a feature verification (`sipi-verify`)
- Preparing a repository for SimPilot the first time
- Checking whether the native `sipi` driver and the simulator are ready
- Creating or fixing `.simpilot/config.json`
- Building and installing the app on the iOS Simulator
- Troubleshooting simulator, UI driver, build, install, or interaction failures

## Workflow

Gate every session on the same sequence — for ad-hoc driving, regression tests (`sipi-test`), and feature checks (`sipi-verify`) alike:

1. Read `docs/preflight.md` and complete its checks. Preflight and `sipi doctor` must both pass before any simulator interaction; if `sipi doctor` fails, report the failing capability and stop.
2. If `.simpilot/config.json` is missing or incomplete, write it (bootstrap detection lives in `docs/build.md`).
3. If the config includes a `build` section, read `docs/build.md` and build/install the app before continuing.
4. Drive the UI with the wrappers from `docs/ui-driver.md`; consult `docs/patterns.md` for the element-interaction fallback chain and control quirks.
5. If any step fails, read `docs/troubleshooting.md` and apply the smallest fix that restores a reliable session.

Why the native driver: the `sipi` wrappers in `docs/ui-driver.md` drive the native binary, which sees both the frontmost app tree and System UI (PhotosPicker, Share Sheet, SFSafariViewController) in one tree. Prefer observed UI (`ui_describe`, `ui_screenshot`) over guessing from source, and re-check after each meaningful action when behavior is flaky. Run `sipi --help` to discover the full command set.

## References

- `docs/preflight.md` for session initialization and config detection
- `docs/ui-driver.md` for reusable UI command functions
- `docs/patterns.md` for the shared element-interaction fallback chain and control-specific quirks
- `docs/build.md` for build/install procedures
- `docs/troubleshooting.md` for common failures and recovery steps
