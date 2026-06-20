# Development — `sipi`

This is the developer guide for the SimPilot package. End users do not build from
source — see the top-level [README](../README.md) for installation.

SimPilot is a native, headless macOS automation toolkit for the iOS Simulator,
built as a single SwiftPM package. It ships the `sipi` CLI plus the three
`sipi-*` agent skills (embedded in the binary) that drive it.

`sipi` drives Apple's **private** Simulator frameworks in-process (accessibility,
HID, framebuffer capture) and **shells out to the public `xcrun simctl`** for
everything that does not require private APIs (app / file / lifecycle). It runs
headless: no GUI, no Node runtime, and no spawned helper process.

## Posture

- **Private frameworks, runtime only.** Exactly three Apple private frameworks
  are loaded at runtime via `dlopen` — CoreSimulator, SimulatorKit
  (Indigo HID + IOSurface framebuffer), and AccessibilityPlatformTranslation
  (APT). They are never linked at build time and never redistributed; they come
  from the user's own Xcode. The full inventory of undocumented symbols, magic
  constants, and their runtime guards is in
  [`private-symbols.md`](private-symbols.md).
- **simctl shell-out for the rest.** App install/launch/terminate/uninstall,
  boot/shutdown/erase, addmedia, privacy, openurl, `ui appearance`, status bar,
  pasteboard, `record-video`, and `log stream` all go through typed `Process()`
  wrappers over `xcrun simctl` — no private APIs (see `SimShell`).

## Package layout

The single package (external dependency: `swift-argument-parser` only) is split
so the private-framework surface stays in one place:

```
SimPilot
├── SimBridge     Objective-C. The ONLY target that touches private symbols /
│                 dlopen. Exposes SPSimBridge / SPFrameCapture to Swift via
│                 include/SimBridge.h. Links public AppKit / QuartzCore /
│                 IOSurface / CoreImage / CoreVideo only.
├── SimCore       Pure Foundation. No SimBridge, no Process(), no private FW.
│                 AX node model + describe-ui JSON encoder, the SimDriver
│                 protocol + value types, the resolver / poller / KeyCode /
│                 TapResolution / gesture+slider geometry / orientation math
│                 (ported from AXe — see ../THIRD_PARTY_LICENSES.md), plus
│                 report generation, result validation, and the embedded-skill
│                 install flow.
├── SimNative     The SimDriver implementation. Wires SimCore value types to
│                 SimBridge's Objective-C APIs.
├── SimShell      Typed Process() wrappers over public `xcrun simctl`.
├── SimSkills     The three skill trees, embedded into the binary at build time.
└── sipi          The swift-argument-parser CLI for the `sipi-*` skills.
```

`SimCore` is framework-agnostic so it stays unit-testable with a mock driver
(`SimCoreTests`) and another backend could be added behind the same `SimDriver`
seam.

## Build and test

A developer editing SimPilot builds and tests from the repository root:

```sh
swift build -c release   # then run the local .build/release/sipi
swift test               # SimCore contract tests + gated integration tests
```

The integration tests under `Tests/SimNativeIntegrationTests` need a booted
simulator; they no-op unless `SIPI_TEST_UDID` names a booted device UDID.

## How the skills are embedded

The three skills (`sipi-common`, `sipi-test`, `sipi-verify`) live under
`.claude/skills` and are compiled into the `sipi` binary, so the install ships a
single self-contained download.

The wiring is the `EmbedSkillsPlugin` build-tool plugin
(`Plugins/EmbedSkillsPlugin`). On every `swift build` of the `SimSkills` target
it runs the `simskillsgen` generator, pointing it at the in-package `skills`
symlink (`Sources/SimSkills/skills` → `../../.claude/skills`) and generating
`EmbeddedSkillsData.swift` (base64 file bytes + executable bits), which SwiftPM
then compiles into `SimSkills`.

Every skill file is declared as an `inputFiles` of the build command, so SwiftPM
re-runs the generator whenever any skill changes — the embedded payload can
never go stale relative to the source tree. `SimCore` depends on `SimSkills`, so
`sipi setup` / `sipi update` materialize the embedded payload onto disk.

## `sipi` CLI

`sipi` is the sole CLI; the skills drive it directly through the `ui_*` /
`native_*` shell helpers in
[`ui-driver.md`](../.claude/skills/sipi-common/docs/ui-driver.md).

### Perception

```sh
sipi describe-ui <udid> [--deep] [--expect "Text"]   # AX tree (default fast; grid on --deep/auto)
sipi describe-point <udid> <x> <y>   # single objectAtPoint hit-test (cheap, no grid)
```

### Input

```sh
sipi tap <udid> ...                  # tap by --label / --id / --value, or coordinates
sipi type <udid> "text"              # KeyCode → HID (non-US via simctl pbcopy + Cmd+V)
sipi key / key-sequence / key-combo  # HID keys, sequences, modifier combos
sipi swipe / touch / drag / gesture  # HID touch phases + gesture presets
sipi multitouch <udid> <phase> ...   # two-finger touch phase (e.g. pinch)
sipi slider <udid> ...               # resolve + drag + AXValue verify
sipi button <udid> <name>            # hardware button (home/lock/side_button/...)
sipi crown <udid> <delta>            # Digital Crown rotation (Apple Watch only)
sipi orientation <udid> [--set name] # native READ; SET (PurpleEvent, osascript fallback)
```

### Capture

```sh
sipi screenshot <udid> <path>        # zero-copy IOSurface PNG
sipi record-video <udid> <path>      # simctl io recordVideo --codec h264 (background + SIGINT)
```

### Devices

```sh
sipi devices                         # JSON device list (native CoreSimulator)
sipi list-simulators                 # device list for skills
```

### Reports and validation

```sh
sipi report <run-dir>                # generate report.html for a sipi-test run
sipi verify-report <verify-dir>      # generate report.html for a sipi-verify run
sipi validate <workspace>            # validate the JSON files in a .simpilot workspace
```

Report generation lives **inside** the binary (`report` / `verify-report` /
`validate`) so a single-binary install stays self-contained; the skill docs
invoke `sipi report …` directly.

### Diagnostics and lifecycle

```sh
sipi doctor [--json]                 # probe native capabilities; exit 0 only if all present
sipi version [--json]                # print the sipi version
sipi setup                           # install the embedded skills into Claude Code + Codex
sipi update                          # download the latest release binary + refresh skills
sipi uninstall                       # remove skills, install metadata, and the sipi binary
```

`sipi doctor` is the workflow gate: it reports the dlopen status of the three
private frameworks, the key classes/symbols each needs, the active Xcode, and any
booted devices, and exits non-zero if any core capability is missing. The exact
exit-code and output contract is pinned in
[`sipi-doctor-contract.md`](sipi-doctor-contract.md); `preflight.md` and the CI
matrix gate on it.

### describe-ui JSON shape

`describe-ui` emits a top-level JSON array (pretty-printed with the spaced-colon
`"key" : "value"` style) so skills can grep it as raw text. Each node may carry
`AXLabel`, `AXValue`, `role_description`, `role`, `subrole`, `type`,
`AXUniqueId`, `enabled`, `frame{x,y,width,height}`, and `children`. The default
path is frontmost + recursive (fast, ~0.1s); the 16pt `objectAtPoint` grid
pass that surfaces System UI (PhotosPicker, status bar, cross-process overlays)
is opt-in via `--deep` or auto-triggered when an `--expect`ed string is missing.

```sh
sipi describe-ui <udid> [--deep]      # accessibility tree as JSON (--deep sees System UI)
sipi tap <udid> --norm -x <nx> -y <ny>
sipi screenshot <udid> <path>
```

End users run the installed `sipi` on PATH; a developer editing SimPilot runs
the locally-built `.build/release/sipi`.

## Requirements

- macOS with Xcode 26+ (private Simulator frameworks loaded from the active Xcode
  / system; override with `DEVELOPER_DIR`).
- A booted Simulator for perception / input / capture commands.

## Notes

- Depends on Apple **private** frameworks loaded via `dlopen`; for local
  development and Simulator-only testing, not App Store distribution.
- `SimCore` ports framework-agnostic logic from AXe (MIT). See
  [`../THIRD_PARTY_LICENSES.md`](../THIRD_PARTY_LICENSES.md).
