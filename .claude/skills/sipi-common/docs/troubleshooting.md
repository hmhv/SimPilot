# Troubleshooting

The canonical home for known failure modes and their recovery steps. Other docs
link here rather than restating them.

## Setup

| Problem | Solution |
|---------|----------|
| `sipi: command not found` / `sipi doctor` fails | Install sipi (`curl -fsSL https://raw.githubusercontent.com/hmhv/SimPilot/main/install.sh \| bash`), or from a checkout `swift build -c release` and use `.build/release/sipi`. `sipi doctor` confirms the core capabilities (CoreSimulator, SimulatorKit HID, AccessibilityPlatformTranslation) |
| install / `swift build` failure | `sudo xcode-select -s /Applications/Xcode.app`, verify with `xcodebuild -version` |
| Simulator not detected | `xcrun simctl boot "iPhone 16 Pro"` — booting needs no window, sipi drives headlessly |
| "Where is the simulator window?" | `sipi open-ui` opens Device Hub (Xcode 27+) or Simulator.app (Xcode ≤26). Do NOT use `open -a Simulator`: Xcode 27 removed Simulator.app, so it fails even while the device is booted and driveable |
| Simulator unresponsive | `xcrun simctl shutdown <udid>; sleep 2; xcrun simctl boot <udid>` |
| Installed `sipi` behaves like an older build | `sipi doctor` notes report the running binary, its timestamp, and warn when the checkout's HEAD is newer. Rebuild + reinstall before concluding a fix does not work |
| Insufficient disk space | Delete old runs, `xcrun simctl delete unavailable`, reduce keep-runs |

## Interaction & Detection

| Problem | Solution |
|---------|----------|
| tap has no effect / element not found | Re-read with `describe-ui` → try `--id` or coordinates. Close any overlay first. Before a blind coordinate tap, confirm what is there with `sipi describe-point --pixel` |
| tap succeeds but no state change | Toggle / Menu / DisclosureGroup → use the method in `patterns.md` |
| Screenshot is black | Confirm Booted. Locked → `sipi button $UDID home`. Still launching → wait longer |
| App crashed | Check the home screen with `describe-ui` → relaunch with `xcrun simctl launch $UDID $BUNDLE_ID` → mark the step FAIL |
| Keyboard not shown / `type` has no effect | Use `sipi set-text $UDID "text" --id <id>` — no keyboard, focus, or pasteboard needed. Reach for `sipi type` only when the keystrokes are the subject; then tap the field to focus it first |
| Cannot interact with alert | Confirm labels with `describe-ui`. Wait ~0.5s. Fall back to coordinates |
| Scroll position off | Use `sipi swipe` to control the amount. Re-read with `describe-ui` after scrolling |
| v2 selector doesn't resolve | Prefer `selector.id`; the runner tries the fast AX tree, then the deep grid. Confirm the id/label with `describe-ui`. `sipi validate` and `run-test` reject a selector that is not exactly one of id / label / value |

### `describe-ui` returns a single empty root

Two different causes. Tell them apart by waiting.

**1. Right after an app launch** — the app has not published its tree yet. Wait and
re-read; measured on iOS 27.0 (24A5408d), three launches in a row read 1 node at
1s and the full tree at 3s. Waiting is the whole fix.

**2. VoiceOver was turned on and then off on this device** — every app that comes
to the foreground afterwards reports an empty root, and it does NOT clear with
time or an app relaunch. SpringBoard keeps reading fine, which makes this look
like an app problem when it is device-wide. **Only a device restart recovers it:**

```bash
xcrun simctl shutdown "$UDID" && xcrun simctl boot "$UDID"
```

Turning VoiceOver back ON also reads fine — it is specifically the OFF state after
an ON that is broken. Measured with a control on iOS 27.0 (24A5408d) / Xcode 27
beta 5: no-VoiceOver 15 nodes, ON 16, ON→OFF 1, ON again 16, OFF again 1, reboot 15.

**Do not use `sipi voiceover --enable`/`--disable` as a "re-prime the bridge"
trick.** Earlier revisions of this document recommended exactly that; on iOS 27 it
is the cause of case 2, not a cure.

Run VoiceOver steps last in a session, and restore according to the baseline you
read BEFORE enabling it (`sipi voiceover "$UDID" --json`):

- **Baseline was on** — leave VoiceOver on. Nothing to undo, no restart: the tree
  reads fine while it is enabled, and turning it off is the thing that breaks it.
- **Baseline unreadable** (`{"enabled": null}`, or `unknown` without `--json`) —
  treat it as off and use the two-step path below.
- **Baseline was off** — both of these, in order:

  ```bash
  sipi voiceover "$UDID" --disable
  xcrun simctl shutdown "$UDID" && xcrun simctl boot "$UDID"
  ```

  The restart alone does not turn VoiceOver off — the setting survives
  shutdown/boot (measured: `--enable`, shutdown, boot, and `voiceover --json`
  still reports `enabled: true`). `--disable` alone leaves the tree broken. Both,
  in that order, end with a readable tree and VoiceOver off.

### Taps return `ok` but nothing happens, on EVERY device

The host `CoreSimulatorService` has been up too long (measured: 10+ days).
`simctl erase` does not help — the service is the broken part.

```bash
xcrun simctl shutdown all
killall -9 com.apple.CoreSimulator.CoreSimulatorService   # respawns automatically
```

Then boot again. This restores touch immediately. A keyboard that is still dead
afterward is the device-age problem below.

### `type` failures

The three messages mean different things, and the right response differs:

| Message | Meaning | Safe to retry? |
|---|---|---|
| `text entry not attempted` | Checked BEFORE anything is typed: no text-entry element in the fast or deep tree, or the tree could not be read at all | **Yes** — nothing was sent |
| `text entry had no effect` | The field's content did not change; the keystrokes did not land | Yes, but expect the same result until the cause is fixed |
| `could not verify text entry` | The text WAS sent but the tree could not be read back | **No** — a blind retry can enter the text twice |

For *not attempted*: tap the field first; a game or custom canvas that exposes no
text element needs `--no-verify` / `"verify-effect": false`. If the tree itself
was unreadable, re-prime it (see above).

For *could not verify*: re-prime the bridge, read the field's actual value with
`describe-ui`, and only then decide.

For *had no effect* — three measured causes, all on Xcode 27.0 beta 4:

1. **A worn-out simulator delivers nothing at all.** Paste (Cmd+V),
   `--keyboard`, `--clear`, and bare `sipi key` are all no-ops while taps still
   work. Measured 2026-08-01: this follows **device age, not the iOS version** —
   a freshly created device types fine on iOS 27.0, long-lived ones fail on both
   iOS 27.0 and 26.4. **`simctl erase` does not fix it, nor does a reboot.**
   Confirm by `simctl create`-ing a replacement; if that one types, retire the
   old device. Meanwhile use `sipi set-text`, which needs no keyboard.
   (`sipi type` detects this and FAILS; bare `sipi key` still returns `ok`.)
2. **Non-Latin IME.** `--keyboard` text stays an uncommitted composition
   (`abc` → `あbc`, discarded when the composition is dismissed). `describe-ui`
   reports composing text in AXValue, so a `verify` can pass on text the field
   never committed.
3. **`--clear` against a pending composition.** Cmd+A goes to the IME and only
   one character is deleted, leaving the old text (`あbc` + clear + `world`
   measured as `あb world`). Send `sipi key 41 "$UDID"` (Escape) first to discard
   the composition.

On a healthy device with no IME, *had no effect* means the field was not focused.

### Typed text lands appended to what was already there

`sipi set-text` replaces the whole value — no clear step needed. With `sipi type`,
`--clear` (or `"clear": true`) selects-all and deletes first, but only when no IME
composition is pending — see cause 3 above.

### A device-state command fails with *needs a devicectl that can target simulators*

`sipi biometrics` / `appearance` / `voiceover`, and the `biometrics` /
`display-state` / `voiceover` test actions, go through `xcrun devicectl`, which
only speaks to simulators from Xcode 27 on. Check with
`xcrun devicectl list plugins` — it must list `SimulatorCoreDevicePlugin`. Select
Xcode 27 or later with `xcode-select`, or use the simctl-backed actions
(`appearance`, `content-size`, `increase-contrast`) instead.

## Build

| Problem | Solution |
|---------|----------|
| Build error is unclear | Re-run the same build without `-quiet` for the full log |
| Signing error | Add `CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO` |
| Unknown scheme | `xcodebuild -list -project MyApp.xcodeproj` |
| SPM dependency resolution failed | `swift package resolve` |

## Execution

| Problem | Solution |
|---------|----------|
| Execution stalls midway | In an ad-hoc Bash call, do not `&&`-chain `sipi` commands — one non-zero exit short-circuits the rest. Use `;` or `\|\|`. Saved tests are unaffected: `run-test` / `run-suite` own the step loop |
| result.json missing | Verify each test writes on completion |
| iPad launches slowly | iPhone ~2s → iPad ~4s |
| Section header uppercase | Match case-insensitively (`grep -qi`) |
| Dark Mode verify fails | Wait 2-3s after changing the setting; iOS 18 applies it slowly |
| System UI won't close | Tap a visible label first. PhotosPicker multiple: `sipi key 40 $UDID` confirms, keycode `41` cancels. FileImporter: `41`. Share Sheet: downward `sipi swipe`. ColorPicker: touch the close button |
| `.borderless` Button fake success (iOS 26+) | All tap methods give fake success inside a List. Remove `.borderless`, or tap the whole row |
