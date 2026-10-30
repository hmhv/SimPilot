# Foldables (iPhone Duo)

Measured on Xcode 27.2 (27B52) / iOS 27.2. An iPhone Duo has **two** built-in screens
and lights exactly one at a time:

| Role | Screen ID | Points | Lit when |
|---|---|---|---|
| `cover` | 1 | 466x678 | shut |
| `inner` | 3 | 669x951 panel, 951x669 as apps see it (landscape-left) | open |

Xcode 27.2 (27B52) drives the Duo on its own runtime, a separate download from the
general iOS 27.2 runtime. Its identifier is `iOS-27-2-iPhone19-4`; `sipi runtime
list` shows it as a second iOS 27.2 row with a different build (24B91016s). To install one,
pass that build to `-buildVersion` (it takes a build as well as a version):

```bash
xcrun simctl list runtimes | grep iPhone19-4   # installed?
xcodebuild -downloadPlatform iOS -buildVersion <Duo build from sipi runtime list> -architectureVariant arm64
xcrun simctl create "iPhone Duo" com.apple.CoreSimulator.SimDeviceType.iPhone-Duo \
    com.apple.CoreSimulator.SimRuntime.iOS-27-2-iPhone19-4
```

The dark one is not absent. It keeps vending a live, solid-black framebuffer, so
reading the wrong screen is never an error — it is a black PNG, or an
accessibility tree describing a screen nobody is looking at. Two habits follow:

- **Check the pose before trusting a size.** A 466x678 tree where you expected
  951x669 is a shut device, not a layout bug. `fold-state` says which it is:

  ```bash
  "$SIPI" fold-state "$UDID"
  # { "foldable": true, "folded": false, "activeDisplay": 3,
  #   "orientation": "landscape-left", "displays": [ … ] }
  ```

  There is no hinge angle in it: Xcode 27.2 has no way to read one.

- **Name the screen when you mean a specific one.** `--display active` (the
  default), `inner`, `cover`, or a screen ID, on both `screenshot` and
  `record-video`:

  ```bash
  "$SIPI" screenshot "$UDID" inner.png --display inner
  "$SIPI" screenshot "$UDID" cover.png --display cover
  ```

  Naming a screen the device does not have is an error, not a silent fallback to
  the other one. A capture of the lit screen is turned the way the screen is held,
  so the inner screen comes back upright at 2853x2007, matching describe-ui.
  A sipi binary older than the checkout returned it rotated (2007x2853);
  rebuild when `doctor` says the binary predates the checkout. `xcrun simctl io
  "$UDID" screenshot --display=3` also captures the inner screen upright
  (`--display=1` is the cover); without `--display` simctl refuses with
  `Cannot choose between 2 displays`, for `recordVideo` too. `No framebuffer image available`
  meant the device had gone to sleep with no screen lit; `fold --open` then
  `--closed` woke it.

- **Fold it yourself when you need the other pose.**

  ```bash
  "$SIPI" fold "$UDID" --closed          # 0° — the cover takes over
  "$SIPI" fold "$UDID" --open            # 180° — the inner screen takes over
  "$SIPI" fold "$UDID" --angle 120       # book pose
  "$SIPI" fold "$UDID" --open --over 1.5 # sweep, for an app that animates on the fold
  ```

  It prints the screen the device actually lit (`inner 669x951pt`), not the one
  asked for, and does not return until the screen handover has landed — so the
  next command sees the new screen. Jumping from either end, 82° and below shows
  the cover and 88° and above the inner screen; in between it depends on the
  direction (opening from 0° hands over at 83°, closing from 180° at 87°), and
  `fold` does not wait there: it returns at once with the old screen, which a
  few seconds later can give way to the other one — read `fold-state` or
  `wait-for` before relying on it. Small
  steps hand over much later: stepping down 5° at a time from 120° kept the inner
  screen lit to 50°. `--over` sweeps from the angle sipi last set on the device,
  or from the lit screen's end when the device was folded some other way.

  Apple exposes no way to do this: simctl and devicectl have no verb for it.
  `fold` builds a small helper with the active Xcode's iPhoneSimulator SDK the
  first time it runs (~1s, then cached under `~/.local/share/simpilot/hinge`). A
  toolchain with no such SDK cannot fold, and `doctor` says so.

**What works on each screen:**

| | cover (shut) | inner (open, and book poses) |
|---|---|---|
| `describe-ui`, `screenshot`, `record-video`, `fold-state` | yes | yes |
| `tap`/`double-tap` by point, `swipe`, `touch`, `drag`, `key`, `type`, `button` | yes | yes |
| `tap`/`double-tap` by `--id`/`--label`/`--value` | yes | yes — sent to the element's frame unchecked |
| `set-text`, `describe-point` | yes | **no** — refused with the reason |
| rotation (`orientation --set`, devicectl, Xcode MCP) | **no** | **no** |

The inner screen answers no accessibility hit-test anywhere on it, while touches
at a frame's point land. A selector tap there skips the usual check of what is
under the point and says so on stderr; check the effect as you would anyway.
`set-text` and `describe-point` are built on the hit-test, so they stop with an
error that says to fold the device shut for them. `doctor` prints this table for
any booted Duo.

Other tools: XCUITest taps both screens (a selector tap changed the app on the
inner screen and on the cover, measured 2026-10-25). Xcode MCP's
`DeviceInteractionSynthesize` taps only the cover, and only in a session opened
while the cover was lit; its screenshot is always the cover. Its typing
(`sipi type --xcode-mcp`) reaches either screen. serve-sim drives both screens (points in
the panel's portrait space). Some trees are incomplete
on the inner screen: a `NavigationSplitView` sidebar's rows, a horizontal
toolbar's items in portrait and the home screen's icon positions were missing or
wrong in `describe-ui` — tap those by position. Rows in a detail column and
ordinary views were fine.

Split View can be entered by touch: on the inner home screen, long-press an
app icon (`touch --down --up --delay 1.5`), tap "Open in Split View" (localized)
— that app takes the left half — then tap a second app on the home screen that
fills the right half. Dragging the divider to an edge leaves Split View. The
home-indicator route does not work from sipi: a `swipe` or `drag` up from the
bottom edge did not even go home, on either screen. Use `button home` to reach
the home screen.

Rotation has no scripted route on a Duo: `xcrun devicectl device orientation
set|rotate` and Xcode MCP's `orientation` each report success and leave both
screens as they were, and `sipi orientation --set` refuses a Duo. Do not call
devicectl's orientation set on one: the first call after a boot takes the
device's input over the way Device Hub does (below). A person can turn it
with Device Hub's rotate button, after which sipi drives it as usual — the cover
on its side takes taps by selector and by point in 678x466 points. Apps that are
portrait-only on iPhone (Settings, the home screen) stay upright on the cover
whichever way it is held.

Each screen keeps its own rotation through folds: with the inner screen turned
to portrait, shutting brought the cover up on its side, and opening again went
back to the inner screen in portrait. A restart puts both back in their default
holds. `fold-state` prints the orientation of the interface, not of the device:
the inner screen in portrait reads `portrait-upside-down` (`rot180`), and the
cover on its side reads `portrait` while a portrait-only app is in front.

**What the Duo simulator cannot do** — checked 2026-10-30 with Xcode 27.2
(27B52) and the iOS 27.2 Duo runtime (24B91016s). Re-check each one when a new
Xcode or Duo runtime ships:

| Not possible | How it showed | Re-check |
|---|---|---|
| Rotation from a script | `devicectl device orientation set` printed "New Device Orientation" while `get` kept the old one; Xcode MCP's `orientation` changed its own report but not the app | `devicectl device orientation set --device "$UDID" landscapeLeft`, then `sipi fold-state` |
| System edge gestures from a script (home, Split View from the home indicator) | `swipe`/`drag` up from the bottom edge left the app in front on both screens | `swipe` from y 0.995 to 0.5, then `describe-ui` |
| Picture in Picture | `AVPictureInPictureController.isPictureInPictureSupported()` is false (an iPhone 18 Pro simulator too) | call it in any app |
| Cameras | `AVCaptureDevice.DiscoverySession` finds no device | same call |
| Reading the hinge angle from outside | `fold-state` carries no angle; only the app's `onHingeChange` sees it | `sipi fold-state` |
| Xcode MCP taps on the inner screen | taps do not land; its screenshot is the cover (typing does land) | one tap, then `xcrun simctl shutdown` + `boot` |
| `set-text`, `describe-point` on the inner screen | refused: the inner screen answers no hit-test | `sipi describe-point` while open |

Not re-checked on this version: AXe and idb (neither was usable here).

**Device Hub takes over input while it is open.** Opening it raises the guest
state `com.apple.coredevice.dtuhidd.active` to 1; from then on taps on the inner
screen are silently dropped (the cover still takes them), and Device Hub keeps
replacing the simulator's pasteboard with the Mac's clipboard — so `type` refuses
to paste rather than type whatever the user last copied. The first
`devicectl device orientation set` after a boot raises the same state. `doctor`
reports it, and `sipi repair-input "$UDID"` clears it (it restarts SpringBoard,
which closes running apps). Afterwards the device shows the cover while the hinge
still reads 180°, so `fold --open` alone changes nothing: run `fold --closed`,
then `fold --open`. Quitting Device Hub shuts down the simulators it was
showing; boot them again afterwards.

**Testing what survives a fold.** A fold is a live resize, not a relaunch, so
state lives or dies with the app's view tree. To test that, put the app in the
state first rather than by tapping there — here through a launch environment
variable the app itself reads (`SCREEN` is the app's own) — then fold and read:

```bash
SIMCTL_CHILD_SCREEN=Settings xcrun simctl launch --terminate-running-process "$UDID" com.example.app
"$SIPI" fold "$UDID" --closed
"$SIPI" describe-ui "$UDID" --format compact
```

An app that writes what it measured (sizes, size classes, a token held in
`@State`) to a file in its Documents directory can be read back with
`xcrun simctl get_app_container "$UDID" <bundle-id> data`.

Such an instrument pays for itself: size, both size classes, safe-area insets,
`toolbarVerticalEdge`, hinge status and angle, every reserved region with
`isActive`, and a counter of size changes, written on every change. Watching
those through one fold shows that a single fold delivers more than one size.
Write from `onChange(of:initial:)` or the geometry action, not from a `.task`
loop: the loop keeps the view value it started with, so the environment values
it reads stay at their launch values.

A pose sweep:

```bash
TEXT="<text only the settled layout shows>"
"$SIPI" fold "$UDID" --open && "$SIPI" wait-for "$UDID" --text "$TEXT" --timeout 5 && "$SIPI" screenshot "$UDID" shot-flat.png --display inner
"$SIPI" fold "$UDID" --angle 128 --over 1.5 && "$SIPI" wait-for "$UDID" --text "$TEXT" --timeout 5 && "$SIPI" screenshot "$UDID" shot-book.png --display inner
"$SIPI" fold "$UDID" --closed && "$SIPI" wait-for "$UDID" --text "$TEXT" --timeout 5 && "$SIPI" screenshot "$UDID" shot-cover.png --display cover
```

`a11y-audit` reads either screen; expect a 38x38pt warning for every system
vertical-bar button and look at the controls the app draws itself.

In long sessions a Duo can drop to Shutdown, and after a reboot the first launch
can sit behind the home screen — launch again. Never run `simctl bootstatus`
without `-b` on a shut-down device; it waits forever.
`xcrun simctl launch --console-pty "$UDID" <bundle-id>` to a file captures
`print` output, another way to watch the sizes a fold delivers.

Everything else — `describe-ui`, `tap`, reading `orientation`, `screenshot` — follows the
lit screen automatically and needs no flag. Read `sipi fold-state` before the
first fold and put the device back in that pose when you are done, so the next
session does not inherit another one.
