# UI Driver

`sipi` is the driver. Call it directly — there is no wrapper layer to define.

Shell state does not persist between Bash calls, so every call that touches the
simulator starts with the two variables it needs:

```bash
SIPI=/Users/you/.local/bin/sipi   # the path preflight printed, verbatim
UDID=<resolved-udid>
```

When preflight resolved a path that is NOT on `PATH`, `"$SIPI"` is mandatory in
every later call — a bare `sipi` is `command not found` there. Other docs write
bare `sipi` for readability; substitute `"$SIPI"` whenever the resolved path is
not on `PATH`.

**Among the UDID-taking driver commands, the UDID position varies** — most take
it first, but four do not:

| Shape | Commands |
|---|---|
| `sipi <cmd> <udid> …` | every driver command in the tables below except the four listed here |
| `sipi <cmd> <arg> <udid>` | `key <keycode>`, `gesture <preset>` |
| `sipi <cmd> --flags… <udid>` | `key-sequence --keycodes`, `key-combo --modifiers --key` |

Workspace and diagnostic commands take **no** UDID positional — `doctor`,
`devices`, `validate <path>`, `run-test <test-path>`, `run-suite`,
`report <run-dir>`, `verify-session`, `open-ui`. Those that need a device take it
as a flag (`run-test --device <udid>`).

`network-condition` is split: `status` takes no UDID, but
`apply <profile> <udid> --bundle-id <id>` and `clear <udid> --bundle-id <id>`
both do.

Run `sipi <cmd> --help` when unsure; the tables below show each exact form.

## Coordinate units

Two flags, never interchangeable:

- `--pixel` — logical points, the same space `describe-ui` reports in `frame`.
  Use this for any coordinate you derived from the tree.
- `--norm` — fractions of the screen, 0…1. Use this for "middle of the screen"
  style targets.

**Only one direction is caught.** `--norm` rejects anything outside 0…1, so
frame-derived points hard-error (`Normalized x=200.0 is out of range`). The
reverse is silent: `--pixel -x 0.5 -y 0.5` is a legal pixel coordinate and taps
the top-left corner. Nothing warns you. Confirm a computed coordinate with
`describe-point` before a blind touch.

## Default path

| Need | Command |
|---|---|
| Read the screen | `"$SIPI" describe-ui "$UDID"` |
| Read the screen cheaply | `"$SIPI" describe-ui "$UDID" --format compact` — one element per line, ~4-5x fewer bytes |
| Wait for a state instead of sleeping | `"$SIPI" wait-for "$UDID" --label "Dashboard" --timeout 10` (also `--id`, `--value`, `--text`, `--absent`) |
| Tap by label / id | `"$SIPI" tap "$UDID" --label "Sign In"` / `--id auth.sign-in` |
| Tap a derived coordinate | `"$SIPI" tap "$UDID" --pixel -x 200 -y 700` |
| Put text in a field | `"$SIPI" set-text "$UDID" "text" --id <id>` |
| Press a key | `"$SIPI" key 40 "$UDID"` |
| Capture the screen | `"$SIPI" screenshot "$UDID" out.png` — add `--max-pixel 600` when you are going to look at it yourself |
| Which screen a foldable is showing | `"$SIPI" fold-state "$UDID"` — read only; see § Foldables |

`describe-ui` reads the frontmost app tree. Pass `--expect "Text"` when a later
grep is looking for specific text: on a miss it auto-escalates to the deeper grid
pass, which also surfaces System UI (PhotosPicker, Share Sheet,
SFSafariViewController). `--deep` forces that pass unconditionally, for
inspection only.

Selector taps (`--label` / `--id` / `--value`, and `sipi slider`) escalate to the
deep tree on their own, so they reach System UI without `--deep`. Prefer observed
UI over guessing from source, and re-read after each meaningful action when
behavior is flaky.

`--format compact` prints the same tree as one line per element —
`Button "Sign In" id="auth.sign-in" frame=(24,88,168,44) hit=(108,110)`, with
`disabled` / `offscreen` only when true — for scanning a screen and picking a
selector. The JSON form is the contract the harness and `--expect` read; use it
whenever a later grep depends on the exact shape.

`wait-for` polls until a condition holds and exits 0, or exits 1 at `--timeout`
(default 10s) with the last unmet reason. It takes exactly one of `--label`,
`--id`, `--value` (exact match with surrounding whitespace trimmed on both
sides, optionally narrowed with `--element-type`) or `--text` (verbatim
substring anywhere in the tree), and `--absent` inverts it. The
semantics are the verify semantics: absence is judged against the deep tree,
presence escalates to it on a miss. Reach for it after any action whose result
lands asynchronously — a navigation, a network round trip, an alert appearing or
dismissing — instead of a guessed `sleep`. **This holds for an ad-hoc Bash session
as much as for a saved test** — a hand-driven probe built from 5–10s sleeps is
where the wall clock actually goes, not in sipi. `describe-ui` costs 0.22s, an app
settles 3.1–3.6s after `simctl launch`, and a warm `shutdown` + `boot` +
`bootstatus -b` costs 6.8s; `sipi-verify/docs/verify-workflow.md` has the full
table and the pattern for waiting on a state that must *stay* absent.

`screenshot --max-pixel N` downscales the PNG so its longest side is at most N
pixels. A device-native capture is 3x and costs a reader far more than the
detail is worth; 600 is plenty to judge a layout. Evidence captures (the harness,
`verify-session capture`) stay full size.

`screenshot` and `record-video` both capture whichever screen the device is
lighting. On a device with one screen — every device but iPhone Duo — there is
nothing to choose and `--display` never needs mentioning.

## Input and gestures

| Need | Command |
|---|---|
| Swipe | `"$SIPI" swipe "$UDID" --norm --start-x .5 --start-y .8 --end-x .5 --end-y .2` |
| Scroll / system edge swipe | `"$SIPI" gesture scroll-down "$UDID"` — presets `scroll-{up,down,left,right}`, `swipe-from-{left,right,top,bottom}-edge` |
| Precise drag (reorder, handle) | `"$SIPI" drag "$UDID" --norm --start-x .. --start-y .. --end-x .. --end-y .. --steps 60` |
| Long press | `"$SIPI" touch "$UDID" --pixel -x .. -y .. --down --up --delay 1.5` |
| Double tap | `"$SIPI" double-tap "$UDID" --label "Map"` (or `--pixel -x .. -y ..`) |
| Pinch / zoom | `"$SIPI" pinch "$UDID" out` (zoom in) / `in` (zoom out) |
| Two-finger non-pinch (rotation) | `"$SIPI" multitouch "$UDID" <phase> x1 y1 x2 y2` — phase `1` begin/move, `2` end |
| Slider to a value | `"$SIPI" slider "$UDID" --label "Volume" --value 75` |
| Hardware button | `"$SIPI" button "$UDID" home` |
| Modifier combo / keycode burst | `"$SIPI" key-combo --modifiers 227 --key 4 "$UDID"` / `"$SIPI" key-sequence --keycodes 11,8,15 "$UDID"` |
| Rotate | `"$SIPI" orientation "$UDID" --set landscape-left` |
| Digital Crown | `"$SIPI" crown "$UDID" <delta>` (watchOS only) |
| What is at this coordinate? | `"$SIPI" describe-point "$UDID" --pixel -x .. -y ..` |

`double-tap` and `pinch` send the composed gesture the guest recognizes; two
separate `tap` calls or hand-assembled `multitouch` phases do not reliably
produce one. `pinch` accepts `--center-x/--center-y`, `--separation`,
`--duration`, and `--steps`.

`describe-point` returns a one-element array, or `[]` when nothing is hit — use
it to confirm a computed coordinate before a blind `touch`.

Text entry: `set-text` is the default and `type` is for when the keystrokes
themselves are under test. The rule and its exceptions live in
`patterns.md` § Text Input.

## Inspection and device state

| Need | Command | Needs Xcode 27 |
|---|---|:---:|
| Mechanical accessibility pass | `"$SIPI" a11y-audit "$UDID"` | — |
| Face ID / Touch ID | `"$SIPI" biometrics "$UDID" <status\|enroll\|unenroll\|match\|no-match>` | Yes |
| Accessibility appearance facets | `"$SIPI" appearance "$UDID" [--reduce-motion on …]` | Yes |
| VoiceOver (read only) | `"$SIPI" voiceover "$UDID"` | — |
| Memory-pressure warning to a running app | `"$SIPI" memory-warning "$UDID" --bundle-id <id>` (or `--pid`) | Yes |

`appearance` reads the current state when given no flag and writes when given
one. `voiceover` only reads: setting it is retired, because on iOS 27 turning it
off after it has been on empties the accessibility tree of every app launched
afterwards until the device restarts, and turning it on changes nothing `describe-ui` can see. `biometrics`
is different again: the operation is a **required positional**, and reading is the
explicit `status` operation. They all say so explicitly when the toolchain is too
old (see
`troubleshooting.md`). Matching a biometric does nothing while the device is
unenrolled.

`memory-warning` delivers what Simulator.app's Debug menu used to: the app gets
`didReceiveMemoryWarning` and the matching notification, so cache eviction and
low-memory recovery can be exercised on demand. It is transient — nothing to
restore — and fails plainly when the app is not running. Device Hub has no such
control, and neither does simctl.

`a11y-audit` works on any supported Xcode. It reports undersized touch targets,
unlabeled controls, ambiguous duplicate labels, meaningless labels, and truncated
text. Only `missing-label` is an error — it is decidable; the rest are warnings
because they are inferences from the tree. Label rules cover DISABLED controls
too (VoiceOver still announces them); the touch-target rule does not (they cannot
be tapped). It runs the deep grid pass by default (~1s per screen) so System UI
and overlays are audited too — `--fast` skips it. It exits non-zero on an
error-severity finding, so it can gate a check directly; `--fail-on none`
inspects without failing, `--json` gives structured output, `--rules` runs a
subset, `--min-touch-target` changes the 44pt threshold. An empty accessibility
tree is a hard error rather than a clean report, so "no findings" always means
the screen was actually inspected.

## Foldables (iPhone Duo)

Measured on Xcode 27.2 RC / iOS 27.2. An iPhone Duo has **two** built-in screens
and lights exactly one at a time:

| Role | Screen ID | Points | Lit when |
|---|---|---|---|
| `cover` | 1 | 466x678 | shut |
| `inner` | 3 | 669x951 panel, 951x669 as apps see it (landscape-left) | open |

Xcode 27.2 RC drives the Duo on its own runtime, a separate download from the
general iOS 27.2 runtime:

```bash
xcrun simctl runtime list            # look for iOS 27.2 (24B91014)
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
  (`--display=1` is the cover); without `--display` simctl captures the cover,
  which is black while the device is open. `No framebuffer image available`
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
  direction (opening from 0° hands over at 83°, closing from 180° at 87°). Small
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
`DeviceInteractionSynthesize` does not reach the inner screen — its tap did not
land and its screenshot was the cover. serve-sim drives both screens (points in
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

Rotation has no scripted route on a Duo: `sipi orientation --set`,
`xcrun devicectl device orientation set|rotate` and Xcode MCP's `orientation`
each report success and leave both screens as they were. A person can turn it
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

**What the Duo simulator cannot do** — checked 2026-10-25 with Xcode 27.2 RC
(27B48) and the iOS 27.2 Duo runtime (24B91014). Re-check each one when a new
Xcode or Duo runtime ships:

| Not possible | How it showed | Re-check |
|---|---|---|
| Rotation from a script | `sipi orientation --set` printed ok; `devicectl device orientation set` printed "New Device Orientation" while `get` kept the old one; Xcode MCP's `orientation` changed its own report but not the app | `devicectl device orientation set --device "$UDID" landscapeLeft`, then `sipi fold-state` |
| System edge gestures from a script (home, Split View from the home indicator) | `swipe`/`drag` up from the bottom edge left the app in front on both screens | `swipe` from y 0.995 to 0.5, then `describe-ui` |
| Picture in Picture | `AVPictureInPictureController.isPictureInPictureSupported()` is false (an iPhone 18 Pro simulator too) | call it in any app |
| Cameras | `AVCaptureDevice.DiscoverySession` finds no device | same call |
| Reading the hinge angle from outside | `fold-state` carries no angle; only the app's `onHingeChange` sees it | `sipi fold-state` |
| Xcode MCP on the inner screen | taps do not land; its screenshot is the cover | one tap, then `xcrun simctl shutdown` + `boot` |
| `set-text`, `describe-point` on the inner screen | refused: the inner screen answers no hit-test | `sipi describe-point` while open |

Not re-checked on this version: AXe and idb (neither was usable here).

**Device Hub takes over input while it is open.** Opening it raises the guest
state `com.apple.coredevice.dtuhidd.active` to 1; from then on taps on the inner
screen are silently dropped (the cover still takes them), and Device Hub keeps
replacing the simulator's pasteboard with the Mac's clipboard — so `type` refuses
to paste rather than type whatever the user last copied. `doctor` reports the
state, and `sipi repair-input "$UDID"` clears it (it restarts SpringBoard, which
closes running apps). Quitting Device Hub shuts down the simulators it was
showing; boot them again afterwards.

**Testing what survives a fold.** A fold is a live resize, not a relaunch, so
state lives or dies with the app's view tree. To test that, put the app in the
state first through its launch environment rather than by tapping there, then
fold and read:

```bash
SIMCTL_CHILD_SCREEN=Settings xcrun simctl launch "$UDID" com.example.app
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

A pose sweep, in bash — zsh does not word-split an unquoted `$args`, so
`--angle 128 --over 1.5` would reach sipi as one argument:

```bash
#!/bin/bash
for pose in "--open:flat:inner" "--angle 128 --over 1.5:book:inner" "--closed:cover:cover"; do
  IFS=: read -r args name display <<< "$pose"
  "$SIPI" fold "$UDID" $args
  "$SIPI" wait-for "$UDID" --text "<text only the settled layout shows>" --timeout 5
  "$SIPI" screenshot "$UDID" "shot-$name.png" --display "$display"
done
```

`a11y-audit` reads either screen; expect a 38x38pt warning for every system
vertical-bar button and look at the controls the app draws itself.

In long sessions a Duo can drop to Shutdown, and after a reboot the first launch
can sit behind the home screen — launch again. Never run `simctl bootstatus`
without `-b` on a shut-down device; it waits forever.
`xcrun simctl launch --console-pty "$UDID" <bundle-id>` to a file captures
`print` output, another way to watch the sizes a fold delivers.

Everything else — `describe-ui`, `tap`, `orientation`, `screenshot` — follows the
lit screen automatically and needs no flag. A harness run records the pose it
found in `run.json` under `device-state.fold-state` and puts the device back in
it afterwards, so a suite that folds never hands the device on in another pose.
