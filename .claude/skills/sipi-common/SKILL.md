---
name: sipi-common
description: Prepares and repairs an iOS Simulator session for SimPilot's native `sipi` driver, drives it ad-hoc, and selects one-off sipi data/evidence commands. Use for requests such as "tap this on the simulator", "put this file in the app Inbox", "inspect what the app saved", "collect this app's crash reports", or "the simulator/driver is broken". Use sipi-test for repeatable saved JSON tests and sipi-verify for a one-off post-change feature check.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

# Shared SimPilot Setup

Session setup, driver readiness, config, build/install, recovery, and ad-hoc
commands — the foundation `sipi-test` and `sipi-verify` both build on.

## Who owns what

`sipi` owns the bridge: target resolution, fast→deep tree escalation, gesture
composition, and coordinate bounds checking. You own intent — what to tap, what
counts as the right screen, and when the observed state contradicts the request.

## sipi or Xcode's MCP tools

When Xcode's MCP server is also connected, split the work like this:

- **Simulators: sipi.** Reading the tree, tapping by selector, typing, folding
  an iPhone Duo, capturing either screen, saved tests. It is headless, needs no
  open Xcode workspace, and leaves the device as it found it.
- **Do not call Xcode's `DeviceInteraction*` tools on a simulator yourself.** Any
  such session — taps alone included — leaves every app launched afterwards with
  an empty accessibility tree until the device restarts. The tools also take
  coordinates only, and on an iPhone Duo they drive the cover even while the
  inner screen is lit.
- **Reach Xcode's service only through sipi's opt-in routes**, last in the
  session or followed by `xcrun simctl shutdown` + `boot`:
  `sipi type --xcode-mcp` for a simulator that stopped accepting keyboard HID,
  `sipi tap --xcode-mcp` for a Duo cover that ignores sipi's taps.
- **Physical devices: Xcode.** sipi drives simulators only.
- **Neither** can tap a Duo's inner screen or rotate a Duo; rotation is Device
  Hub's rotate button.

## When to use

- Ad-hoc driving that is neither a regression test (`sipi-test`) nor a feature
  check (`sipi-verify`) — tap something, describe the screen, take a screenshot
- Preparing a repository for SimPilot the first time
- Checking whether the native driver and the simulator are ready
- Creating or fixing `.simpilot/config.json`
- Building and installing the app
- One-off app/App Group, Files.app, xcappdata, or crash-evidence operations
- Recovering from a simulator, driver, build, or interaction failure

## Workflow

Every session runs this sequence, ad-hoc or otherwise:

1. Complete `docs/preflight.md`. It is the gate — nothing touches the simulator
   until it passes.
2. Write `.simpilot/config.json` if it is missing or incomplete (detection lives
   in `docs/build.md`).
3. If the config has a `build` section, build and install per `docs/build.md`.
4. Read `.simpilot/notes.md` if it exists — app-specific quirks earlier sessions
   left (§ Project notes in `docs/patterns.md`). Drive with the commands in
   `docs/ui-driver.md`; `docs/patterns.md` has the fallback chain and
   per-control quirks. When this app needed a workaround the patterns do not
   cover, append one line to `.simpilot/notes.md`.
5. For one-off data or evidence work, inspect the installed CLI instead of
   memorizing syntax: start with `sipi --help`, then run
   `sipi help container`, `sipi help files-app`, `sipi help xcappdata`, or
   `sipi help crash-evidence` and the selected nested command's help. Keep
   operations already supplied by simctl as direct `xcrun simctl` commands.
6. On failure, apply the smallest fix in `docs/troubleshooting.md` that restores
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
