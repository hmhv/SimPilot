---
name: sipi-common
description: Drives the iOS Simulator with SimPilot's native `sipi` driver — read the screen, tap, type, fold, capture, put files in the app, read what it saved, collect crash reports — and manages the Xcode and simulator toolchain around it — install Xcode releases, download or delete simulator runtimes, clean up DerivedData and other developer data. Use for requests such as "tap this on the simulator", "check this screen", "build and run it on the simulator", "put this file in the app Inbox", "collect this app's crash reports", "install Xcode 27.2", "download the iOS runtime", "clean up Xcode's disk usage", or "the simulator/driver is broken".
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

# SimPilot

Drive the iOS Simulator, and keep the Xcode and simulator toolchain behind it
installed and clean. How to check the result is yours to decide: read the
screen, capture it, read what the app saved.

## Who owns what

`sipi` owns the bridge: target resolution, fast→deep tree escalation, gesture
composition, and coordinate bounds checking. You own intent — what to tap, what
counts as the right screen, and when the observed state contradicts the request.

## sipi or Xcode's MCP tools

When Xcode's MCP server is also connected, split the work like this:

- **Simulators: sipi.** Reading the tree, tapping by selector, typing, folding
  an iPhone Duo and driving both of its screens, capturing either screen. It is
  headless and needs no open Xcode workspace.
- **Do not call Xcode's `DeviceInteraction*` tools on a simulator yourself.** Any
  such session — one tap is enough — leaves every app launched afterwards with
  an empty accessibility tree until the device restarts (measured on Xcode
  27.2). The tools also take coordinates only, and on an iPhone Duo they reach
  the cover only.
- **Reach Xcode's service only through sipi's opt-in route**, last in the
  session or followed by `xcrun simctl shutdown` + `boot`:
  `sipi type --xcode-mcp` for a simulator that stopped accepting keyboard HID.
- **Physical devices: Xcode.** sipi drives simulators only.
- **Neither** can rotate a Duo; a person can, with Device Hub's rotate button.

## When to use

- Driving an app on the simulator — tap something, describe the screen, take a
  screenshot, check that a change works
- Preparing a repository for SimPilot the first time
- Checking whether the native driver and the simulator are ready
- Creating or fixing `.simpilot/config.json`
- Building and installing the app
- One-off app/App Group, Files.app, xcappdata, or crash-evidence operations
- Recovering from a simulator, driver, build, or interaction failure
- Installing, selecting, or removing Xcode; downloading or deleting simulator
  runtimes; creating devices (`docs/xcode.md`)
- Freeing disk space taken by Xcode and the simulators (`docs/clean.md`)

## Workflow

Every session that drives a simulator runs this sequence. Toolchain work
(`docs/xcode.md`, `docs/clean.md`) needs only the `SIPI=` lookup in preflight
step 1, without `doctor`.

1. Complete `docs/preflight.md`. It is the gate — nothing touches the simulator
   until it passes.
2. When the request involves an app, write `.simpilot/config.json` if it is
   missing or incomplete (detection lives in `docs/build.md`).
3. Build and install per `docs/build.md` only when the request needs the
   current code (preflight step 4).
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
| `docs/preflight.md` | Every session that drives a simulator, before anything else |
| `docs/ui-driver.md` | Before the first UI interaction |
| `docs/foldables.md` | Before driving an iPhone Duo (two screens) |
| `docs/patterns.md` | Choosing how to hit a control, or when a tap misbehaves |
| `docs/build.md` | Building or installing |
| `docs/troubleshooting.md` | Any failure — the canonical list of known modes |
| `docs/xcode.md` | Installing or removing Xcode, simulator runtimes, devices |
| `docs/clean.md` | Freeing disk space taken by Xcode and the simulators |
