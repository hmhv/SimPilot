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
3. If `.simpilot/config.json` is missing or incomplete, detect the project/workspace, detect the scheme, and write the config.
4. If the config includes a `build` section, read `docs/build.md` and build/install the app before continuing.
5. If any step fails, read `docs/troubleshooting.md` and apply the smallest fix that restores a reliable session.

## AXe In This Workflow

This skill does not replace the `axe` skill. It defines when AXe is required and how it fits into SimPilot:

- Use AXe only after preflight succeeds
- Use AXe to confirm simulator state before acting
- Prefer AXe-driven verification over guessing from source alone
- Re-check the UI after each meaningful action when debugging flaky behavior

Common AXe uses in SimPilot sessions:

- `describe-ui` to inspect the current screen
- `screenshot` to confirm layout or visual state
- `tap`, `touch`, `swipe`, and button/key actions for interaction

Refer to the `axe` skill for command syntax and device interaction details.

## References

- `docs/preflight.md` for session initialization and config detection
- `docs/build.md` for build/install procedures
- `docs/troubleshooting.md` for common failures and recovery steps
