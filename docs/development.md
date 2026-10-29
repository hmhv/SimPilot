# Development — `sipi`

This is the developer guide for the SimPilot package. End users do not build from
source — see the top-level [README](../README.md) for installation.

SimPilot is a native, headless macOS automation toolkit for the iOS Simulator,
built as a single SwiftPM package. It ships the `sipi` CLI plus the
`sipi-common` agent skill (embedded in the binary) that drives it, and installs
Xcode releases.

`sipi` drives Apple's **private** Simulator frameworks in-process (accessibility,
HID, framebuffer capture) and **shells out to the public `xcrun simctl`** for
everything that does not require private APIs (app / file / lifecycle). It runs
headless — no GUI and no Node runtime — except `sipi xcode install`, which opens
a sign-in window.

## Posture

- **Private frameworks, runtime only.** Exactly three Apple private frameworks
  are loaded at runtime via `dlopen` — CoreSimulator, SimulatorKit
  (Indigo HID + IOSurface framebuffer), and AccessibilityPlatformTranslation
  (APT). They are never linked at build time and never redistributed; they come
  from the user's own Xcode. The full inventory of undocumented symbols, magic
  constants, and their runtime guards is in
  [`private-symbols.md`](private-symbols.md).
- **Public-tooling shell-out for the rest.** App install/terminate/uninstall,
  shutdown/erase, app containers, `ui appearance`, pasteboard, `record-video`,
  and the guest `launchctl list` (to turn a bundle id into a pid) go through
  typed `Process()` wrappers over `xcrun simctl` — no private APIs (see
  `SimShell`). Everything else simctl already does, the skill runs directly. `DeviceCtl` wraps
  `xcrun devicectl` the same way for the facets simctl never exposed: face-up /
  face-down orientation, biometric enrollment and match events, reading
  VoiceOver, the full accessibility appearance surface, and per-process memory
  warnings.

## Package layout

The single package (external dependency: `swift-argument-parser` only) is split
so the private-framework surface stays in one place:

```
SimPilot
├── SimBridge     Objective-C. The only target that touches private symbols /
│                 dlopen (apart from the guest-side hinge helper SimShell builds). Exposes SPSimBridge / SPFrameCapture to Swift via
│                 include/SimBridge.h. Links public AppKit / QuartzCore /
│                 IOSurface / CoreImage / CoreVideo only.
├── SimCore       Public system frameworks only (Foundation, CoreGraphics, ImageIO, CryptoKit).
│                 No SimBridge, no Process(), no private FW.
│                 AX node model + describe-ui JSON encoder, the SimDriver
│                 protocol + value types, the resolver / poller / KeyCode /
│                 TapResolution / gesture+slider geometry / orientation math
│                 (ported from AXe — see ../THIRD_PARTY_LICENSES.md), plus
│                 the embedded-skill install flow.
├── SimNative     The SimDriver implementation. Wires SimCore value types to
│                 SimBridge's Objective-C APIs.
├── SimShell      Typed Process() wrappers over public `xcrun simctl` and
│                 `xcrun devicectl`.
├── SimSkills     The sipi-common skill tree, embedded into the binary at build time.
└── sipi          The swift-argument-parser CLI the sipi-common skill drives.
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

The `sipi-common` skill lives under `.claude/skills` and is compiled into the `sipi` binary, so the install ships a
single self-contained download.

The wiring is the `EmbedSkillsPlugin` build-tool plugin
(`Plugins/EmbedSkillsPlugin`). On every `swift build` of the `SimSkills` target
it runs the `simskillsgen` generator, pointing it at the in-package `skills`
symlink (`Sources/SimSkills/skills` → `../../.claude/skills`) and generating
`EmbeddedSkillsData.swift` (base64 file bytes + executable bits), which SwiftPM
then compiles into `SimSkills`. It also embeds `LICENSE` and
`THIRD_PARTY_LICENSES.md`, which `sipi licenses` prints, so the released binary
carries the notices for the code it contains.

Every skill file is declared as an `inputFiles` of the build command, so SwiftPM
re-runs the generator whenever any skill changes — the embedded payload can
never go stale relative to the source tree. `SimCore` depends on `SimSkills`, so
`sipi setup` / `sipi update` materialize the embedded payload onto disk.

## `sipi` CLI

`sipi` is the sole CLI; the skill calls it directly, as
[`ui-driver.md`](../.claude/skills/sipi-common/docs/ui-driver.md) describes.

### Perception

```sh
sipi describe-ui <udid> [--deep] [--expect "Text"]   # AX tree (default fast; grid on --deep/auto)
sipi describe-ui <udid> --format compact   # same tree, one element per line (type, label, id, value, frame, hit)
sipi describe-point <udid> [--pixel] -x <x> -y <y>   # single objectAtPoint hit-test (cheap, no grid; normalized unless --pixel)
sipi wait-for <udid> --label "Text" [--timeout 10] [--absent]   # poll until a condition holds; exit 1 at the deadline
sipi a11y-audit <udid>                     # mechanical accessibility rules over the same tree
```

### Input

```sh
sipi tap <udid> ...                  # tap by --label / --id / --value, or coordinates
sipi double-tap <udid> ...           # same targeting; two taps inside the system double-tap window
sipi type <udid> "text"              # paste via simctl pbcopy + Cmd+V (default); --keyboard = KeyCode → HID (US only); --clear = Cmd+A + delete first; fails when the field's content did not change (--no-verify opts out)
sipi set-text <udid> "text" --id <id> # write the field's AX value (no keyboard/pasteboard/focus; verified against the app)
sipi key / key-sequence / key-combo  # HID keys, sequences, modifier combos
sipi swipe / touch / drag / gesture  # HID touch phases + gesture presets
sipi multitouch <udid> <phase> ...   # raw two-finger touch phase
sipi pinch <udid> <in|out>           # interpolated two-finger pinch over multitouch
sipi slider <udid> ...               # resolve + drag + AXValue verify
sipi button <udid> <name>            # hardware button (home/lock/side_button/...)
sipi crown <udid> <delta>            # Digital Crown rotation (Apple Watch only)
sipi orientation <udid> [--set name] # native READ; SET (PurpleEvent → devicectl); --json --physical adds the flat states
```

### Accessibility and device state

```sh
sipi a11y-audit <udid>               # mechanical audit: touch targets, labels, truncation (--fast, --rules, --min-touch-target, --fail-on)
sipi biometrics <udid> <op>          # status | enroll | unenroll | match | no-match      (devicectl)
sipi appearance <udid> [facets]      # read/write reduce-motion, color filters, Liquid Glass, … (devicectl)
sipi voiceover <udid>                # READ VoiceOver state; setting it is retired        (devicectl)
sipi memory-warning <udid> --bundle-id <id>   # memory-pressure warning to a running app  (devicectl)
```

### Capture

```sh
sipi screenshot <udid> <path> [--max-pixel N]   # zero-copy IOSurface PNG; --max-pixel downscales for a reader
sipi record-video <udid> <path>      # simctl io recordVideo --codec h264 (background + SIGINT)
```

### App data and evidence

```sh
sipi container ...                   # safe app data/App Group copy, inspect, snapshot, diff, cleanup
sipi files-app ...                   # experimental File Provider Storage discovery/copy/cleanup
sipi xcappdata ...                   # create/validate; install with simctl directly
sipi crash-evidence ...              # collect app-specific crash reports created since a timestamp
```

These are not aliases for existing simctl commands. See
[`data-artifacts.md`](data-artifacts.md) for the path-safety contract and the
inspection formats.

### Devices

```sh
sipi devices                         # JSON device list (native CoreSimulator)
sipi list-simulators                 # device list for skills
```

### Xcode

```sh
sipi xcode list                      # Xcode releases Apple offers (from xcodereleases.com)
sipi xcode install <build>           # download from Apple (sign-in window) + install into /Applications
sipi xcode uninstall <build>         # move an installed Xcode to the Trash (not the selected one)
sipi runtime list [--platform iOS]   # simulator runtimes Apple offers, installed ones marked
```

Everything else about Xcode, runtimes, and cleanup is plain `xcode-select` /
`xcodebuild` / `simctl`; the skill's `xcode.md` and `clean.md` describe it.

### Diagnostics and lifecycle

```sh
sipi doctor [--json]                 # probe native capabilities; exit 0 only if all present
sipi version [--json]                # print the sipi version
sipi open-ui [--json|--print-only]   # open Device Hub
sipi repair-input <udid>             # reconnect touch/keys after Device Hub took them over (restarts SpringBoard)
sipi setup                           # install the embedded skills into Claude Code + Codex
sipi update                          # download the latest release binary + refresh skills
sipi uninstall                       # remove skills, install metadata, and the sipi binary
```

`sipi doctor` is the workflow gate: it reports the dlopen status of the three
private frameworks, the key classes/symbols each needs, the active Xcode, and any
booted devices, and exits non-zero if any core capability is missing. The exact
exit-code and output contract is pinned in
[`sipi-doctor-contract.md`](sipi-doctor-contract.md); `preflight.md` gates on
it.

### describe-ui JSON shape

`describe-ui` emits a top-level JSON array (pretty-printed with the spaced-colon
`"key" : "value"` style) so skills can grep it as raw text. Each node may carry
`AXLabel`, `AXValue`, `role_description`, `role`, `subrole`, `type`,
`AXUniqueId`, `enabled`, `frame{x,y,width,height}`, `hitPoint{x,y}`,
`onscreen`, and `children`. The default path is frontmost + recursive (fast,
~0.2s); the 16pt `objectAtPoint` grid pass that surfaces System UI
(PhotosPicker, status bar, cross-process overlays) is opt-in via `--deep` or
auto-triggered when an `--expect`ed string is missing.

`frame` is what the element reports about itself, and it is not a tap target.
It can extend past the display (a row scrolled out of view, a control taller
than the screen), and elements inside a cross-process remote view — a share
sheet — report frames in that view's own coordinate space. `hitPoint` is
always a point on the screen: the grid records the coordinate that hit-tested
to the element when its frame turns out not to be in screen space, and
everything else gets the centre of the frame clipped to the display.
`onscreen` is false for an element with no visible area at all, and such an
element carries no `hitPoint` — there is no honest point to offer for
something that cannot be touched. Selector-based `tap` scrolls those into view
before touching them, and fails if it cannot.

Grid discovery sweeps points in the tree's LOGICAL space but hands them to a
hit-test that reads PHYSICAL portrait coordinates. Those agree only in
portrait, so probe-derived hit points are discarded on a rotated device (and
`--deep` discovery is unreliable there for the same reason).

```sh
sipi describe-ui <udid> [--deep]      # accessibility tree as JSON (--deep sees System UI)
sipi tap <udid> --norm -x <nx> -y <ny>
sipi screenshot <udid> <path>
```

End users run the installed `sipi` on PATH; a developer editing SimPilot runs
the locally-built `.build/release/sipi`.

## Requirements

- macOS with Xcode 27.2+ (private Simulator frameworks loaded from the active Xcode
  / system; override with `DEVELOPER_DIR`).
- A booted Simulator for perception / input / capture commands.

## Notes

- Depends on Apple **private** frameworks loaded via `dlopen`; for local
  development and Simulator-only testing, not App Store distribution.
- `SimCore` ports framework-agnostic logic from AXe (MIT). See
  [`../THIRD_PARTY_LICENSES.md`](../THIRD_PARTY_LICENSES.md).
