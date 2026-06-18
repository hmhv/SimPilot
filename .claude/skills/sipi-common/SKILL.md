---
name: sipi-common
description: Shared setup, initialization, build/install, and troubleshooting workflow for SimPilot simulator skills. Use for preparing the iOS Simulator session, checking AXe prerequisites, creating or fixing `.simpilot/config.json`, building and installing the app, and resolving common simulator or AXe problems.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

# Shared SimPilot Setup

Use this skill for the common workflow behind `sipi-test` and `sipi-verify`.
It covers session initialization, AXe prerequisites, simulator readiness, `.simpilot/config.json`, build/install, and recovery when the workflow breaks.

## When To Use

- Preparing a repository for SimPilot the first time
- Checking whether AXe and the simulator are ready
- Creating or fixing `.simpilot/config.json`
- Building and installing the app on the iOS Simulator
- Troubleshooting simulator, AXe, build, install, or interaction failures

## Core Workflow

1. Read `docs/preflight.md` and complete all checks.
2. Before any simulator interaction, read the `axe` skill. If it is unavailable, stop and tell the user it is required.
3. Read `docs/ui-driver.md` and use its shell prelude for every Bash call that inspects or taps UI.
4. If `.simpilot/config.json` is missing or incomplete, detect the project/workspace, detect the scheme, and write the config.
5. If the config includes a `build` section, read `docs/build.md` and build/install the app before continuing.
6. If any step fails, read `docs/troubleshooting.md` and apply the smallest fix that restores a reliable session.

## AXe In This Workflow

This skill does not replace the `axe` skill. It defines when AXe is required and how it fits into SimPilot.
For UI inspection and label/id taps, use the functions from `docs/ui-driver.md`.
Those functions use AXe first and automatically fall back to the native bridge for System UI that AXe cannot see.
Use direct `axe` commands for screenshots, launch/state helpers, video, and raw gestures that the UI driver does not wrap.

- Use AXe only after preflight succeeds
- Use `ui_describe` to confirm simulator state before acting
- Prefer observed UI verification over guessing from source alone
- Re-check the UI after each meaningful action when debugging flaky behavior

Common AXe uses in SimPilot sessions:

- `ui_describe` to inspect the current screen
- `screenshot` to confirm layout or visual state
- `ui_tap_label` and `ui_tap_id` for label-addressable interaction
- `ui_key` and `ui_screenshot` for key events and captures
- `native_tap`, `native_swipe`, `native_button`, `native_key`, `native_orientation`, and `native_screenshot` when direct native input is more efficient
- `axe touch`, `axe swipe`, and button/key actions for raw interaction

Refer to the `axe` skill for command syntax and device interaction details.

## References

- `docs/preflight.md` for session initialization and config detection
- `docs/ui-driver.md` for reusable UI command functions
- `docs/build.md` for build/install procedures
- `docs/troubleshooting.md` for common failures and recovery steps
