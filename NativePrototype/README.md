# SimPilot Native Bridge

A headless macOS bridge for driving the iOS Simulator from shell scripts. It is
designed for the `sipi-*` skills: use AXe for normal app UI, then automatically
fall back to this native bridge when AXe cannot inspect or act on System UI such
as PhotosPicker, Share Sheet, SFSafariViewController, ASWebAuthenticationSession,
status bar content, and cross-process overlays.

The bridge loads Apple private Simulator frameworks in-process. There is no GUI,
no WebView, no Node runtime, and no spawned helper process.

## What It Provides

- **Device discovery** through CoreSimulator.
- **System UI accessibility** through AccessibilityPlatformTranslation, converted
  into an AX tree compatible with the `serve-sim` `/ax` shape.
- **Simulator input** through SimulatorKit HID: tap, swipe, Home, Lock, App
  Switcher, Siri, Swipe Home, keyboard, multi-touch, Digital Crown, and
  orientation via Simulator.app's Orientation menu.
- **Framebuffer screenshots** through IOSurface to PNG.

Use `Scripts/sipi-ui` or the skill `ui-driver.md` functions first. Call
`.build/debug/sipi-bridge` directly when you need a low-level primitive.

## Targets

- `SimBridge` (Objective-C) — the reusable native core. `dlopen`s the private
  frameworks at runtime (no build-time linkage). API in `Sources/SimBridge/include/SimBridge.h`.
- `sipi-bridge` (Swift executable) — the headless CLI over the core. It runs one
  command and exits.
- `Scripts/sipi-ui` (Bash) — an AXe-first front end that falls back to native AX
  and native taps when AXe is blind.

## Build

```sh
cd NativePrototype
swift build
```

## Recommended Use

For skills and repeatable Bash workflows, read
`../.claude/skills/sipi-common/docs/ui-driver.md` and use its functions:

```sh
ui_describe                         # AXe first; native fallback for System UI
ui_describe --expect "Cancel"       # native fallback when AXe misses expected text
ui_tap_label "Cancel"               # AXe label tap; native frame tap on AXe miss
ui_tap_id "done-button"
ui_key 41                           # native key if available, AXe fallback
ui_screenshot /tmp/shot.png         # native IOSurface screenshot if available
native_orientation landscape-left   # Simulator.app orientation command
```

Use `sipi-ui` directly when you only need inspect/tap behavior:

```sh
Scripts/sipi-ui describe <udid>
Scripts/sipi-ui describe <udid> --expect "Cancel"
SIPI_UI_FORCE_NATIVE=1 Scripts/sipi-ui describe <udid>
Scripts/sipi-ui tap <udid> --label "Cancel"
Scripts/sipi-ui tap <udid> --id "done-button"
Scripts/sipi-ui tap <udid> -x 0.5 -y 0.8
```

## Low-Level CLI

```sh
.build/debug/sipi-bridge devices                       # JSON device list
.build/debug/sipi-bridge ax <udid>                      # accessibility tree as JSON (sees System UI)
.build/debug/sipi-bridge tap <udid> <nx> <ny>           # normalized 0...1
.build/debug/sipi-bridge swipe <udid> <x1> <y1> <x2> <y2>
.build/debug/sipi-bridge button <udid> home|app_switcher|siri|lock|side_button|swipe_home
.build/debug/sipi-bridge key <udid> <hid-usage>
.build/debug/sipi-bridge orientation <udid> portrait|landscape-left|landscape-right|portrait-upside-down
.build/debug/sipi-bridge multitouch <udid> <phase> <x1> <y1> <x2> <y2>
.build/debug/sipi-bridge crown <udid> <delta>             # Apple Watch simulators only
.build/debug/sipi-bridge screenshot <udid> <path>
```

Coordinates for `tap`, `swipe`, and `multitouch` are normalized screen
coordinates in the `0...1` range.

`orientation` uses Simulator.app UI automation rather than an in-process
CoreSimulator call. It requires Simulator.app and macOS accessibility automation
permission for the calling shell/app.

## Fallback Behavior

`sipi-ui describe` falls back to native AX when:

- AXe returns only a tiny tree, usually just the app root.
- `--expect "Text"` is supplied and AXe output does not contain that text.
- AXe appears to be describing the simulator shell instead of the app.
- `SIPI_UI_FORCE_NATIVE=1` or `--native` is set.

`sipi-ui tap --label/--id` falls back when AXe reports no matching accessibility
element. The fallback finds the matching native AX node, computes the frame
center, and taps normalized coordinates through `sipi-bridge`.

## Native bridge vs AXe (measured)

| Pattern | Native (`sipi-bridge`) | AXe |
|---|---|---|
| Normal-app AX (Settings) | ~comparable nodes, ~1.0s | ~0.15s (≈6× faster) |
| System-UI AX (PhotosPicker) | 24 nodes (full picker) | 1 node (app root only) |
| Tap a System-UI element | works | "no element matched", no tap |
| 10 taps latency | 0.53s (in-process) | 1.35s (per-command spawn) |
| Tap by label/id | no (coordinate only) | yes |
| Orientation | Simulator.app menu automation | Simulator.app/menu workflows |

Use AXe for fast, label-addressable, scripted normal-app testing; the native
bridge for System UI (inspect + act) and high-throughput sequences. `sipi-ui`
combines both automatically.

## Requirements

- macOS with Xcode 26+ (private Simulator frameworks loaded from the active Xcode / system).
- A booted Simulator. `axe` on PATH (for `sipi-ui`).
- macOS accessibility automation permission when using `orientation`.

## Notes

- Depends on Apple **private** frameworks loaded via `dlopen`; local development only,
  not App Store distribution. See `THIRD_PARTY_NOTICES.md`.
- Informed by inspecting `serve-sim` (Apache-2.0) to identify relevant private
  symbols, but contains no copied serve-sim source. See `THIRD_PARTY_NOTICES.md`.
