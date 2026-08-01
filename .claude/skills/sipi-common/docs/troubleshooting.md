# Troubleshooting

## Setup

| Problem | Solution |
|---------|----------|
| `sipi: command not found` / `sipi doctor` fails | Install sipi (`curl -fsSL https://raw.githubusercontent.com/hmhv/SimPilot/main/install.sh \| bash`), or from a checkout run `swift build -c release` and set `SIPI` to `.build/release/sipi`. Run `sipi doctor` to confirm the core capabilities (CoreSimulator, SimulatorKit HID, AccessibilityPlatformTranslation) are present |
| install / `swift build` failure | `sudo xcode-select -s /Applications/Xcode.app`, verify with `xcodebuild -version` |
| Simulator not detected | `xcrun simctl boot "iPhone 16 Pro"` (booting needs no window — sipi drives headlessly) |
| "Where is the simulator window?" | `sipi open-ui` opens Device Hub (Xcode 27+) or Simulator.app (Xcode ≤26). Do NOT use `open -a Simulator`: Xcode 27 removed Simulator.app, so it fails with "Unable to find application named 'Simulator'" even while the device is booted and driveable |
| Simulator unresponsive | `xcrun simctl shutdown <udid>; sleep 2; xcrun simctl boot <udid>` |
| Installed `sipi` behaves like an older build | Run `sipi doctor` and read its notes: inside a SimPilot checkout it reports the running binary, its timestamp, and warns when the checkout's HEAD is newer than the binary. Rebuild + reinstall before concluding a fix does not work |
| Insufficient disk space | Delete old runs, `xcrun simctl delete unavailable`, reduce keep-runs |

## Interaction & Detection

| Problem | Solution |
|---------|----------|
| tap has no effect / element not found | Check with `ui_describe` → use `ui_tap_id` or coordinates. Close any overlays first. Before a blind coordinate tap, confirm what is actually at the spot with `ui_describe_point` (`sipi describe-point --pixel`) |
| tap succeeds but no state change | Toggle/Menu/DisclosureGroup → use the correct method from `patterns.md` |
| Screenshot is black | Verify Booted state. Locked → `native_button home` (or `sipi button $UDID home`). Still launching → add sleep |
| App crashed | Check home screen with `ui_describe` → relaunch with `xcrun simctl launch $UDID $BUNDLE_ID` → mark the step FAIL |
| Keyboard not shown / type has no effect | Use `sipi set-text $UDID "text" --id <id>` — it needs no keyboard, focus, or pasteboard and is the default for putting content in a field. Only reach for `sipi type` when the keystrokes are the subject; then tap by coordinate to focus first (the default paste path is layout/IME independent, `--keyboard` can be eaten by a non-US layout) |
| `type` fails with *text entry had no effect … the text field's content did not change* | The simulator has stopped delivering keyboard HID: paste (Cmd+V), `--keyboard`, and `--clear` all no-op while taps still work. Measured 2026-08-01 on Xcode 27.0 beta 4: this follows **device age, not the iOS version** — a freshly created device types fine on iOS 27.0, long-lived ones fail on both iOS 27.0 and 26.4. **`simctl erase` does NOT fix it, nor does a reboot.** Confirm by `simctl create`-ing a replacement device; if that one types, retire the old device. Meanwhile use `sipi set-text $UDID "text" --id <id>`, which writes the accessibility value and needs no keyboard. On a healthy device the same failure means the field was not focused — tap it first |
| Taps return `ok` but nothing happens, on EVERY device | The host `CoreSimulatorService` has been up too long (measured: 10+ days). `simctl erase` does not help — the service is the broken part. Fix: `xcrun simctl shutdown all` then `killall -9 com.apple.CoreSimulator.CoreSimulatorService` (it respawns automatically), then boot again. This restores touch immediately; a keyboard that is still dead afterward is the device-age problem above |
| `describe-ui` returns a single empty root (degenerate tree) | Very common right after an app launch, on both iOS 26 and 27. Re-prime the accessibility bridge: `sipi voiceover $UDID --enable` then `--disable`, wait ~2s, and re-read. Note this can leave a "VoiceOver gestures" system alert on screen — dismiss it (`sipi tap $UDID --label OK`) before continuing |
| `type` fails with *text entry not attempted* | Checked BEFORE anything is typed, so nothing was sent and a retry is safe. Either no text-entry element was found in the fast or deep tree (tap the field first; a game or custom canvas that exposes none needs `--no-verify` / `"verify-effect": false`), or the accessibility tree could not be read at all — re-prime it with `sipi voiceover $UDID --enable` then `--disable` |
| `type` fails with *could not verify text entry* | The text WAS sent but the tree could not be read back, so whether it landed is unknown. **Do not blindly retry** — a second run can enter the text twice. Re-prime the accessibility bridge (`sipi voiceover $UDID --enable` then `--disable`), check the field's actual value with `sipi describe-ui`, and only then decide |
| A device-state command fails with *needs a devicectl that can target simulators* | `sipi biometrics` / `appearance` / `voiceover` and the `biometrics` / `display-state` / `voiceover` test actions go through `xcrun devicectl`, which only speaks to simulators from Xcode 27 on. Check with `xcrun devicectl list plugins` — it must list `SimulatorCoreDevicePlugin`. Select Xcode 27 or later with `xcode-select`, or use the simctl-backed actions (`appearance`, `content-size`, `increase-contrast`) instead |
| Typed text lands appended to what was already there | `sipi set-text` replaces the whole value — no clear needed. With `sipi type`, `--clear` (or `"clear": true`) selects-all + deletes first, but only when no IME composition is pending: with one, Cmd+A goes to the IME and a single character is deleted, leaving the old text (`あbc` + clear + `world` → `あb world`). Send `sipi key 41` (Escape) first to discard a composition |
| Cannot interact with alert | Verify labels with `ui_describe`. Add sleep 0.5. Fall back to coordinates if not visible |
| Scroll position off | Use `sipi swipe` (or `native_swipe`) to control amount. Verify with `ui_describe` after scrolling |
| v2 selector doesn't resolve | Prefer `selector.id`; the runner tries the fast AX tree, then the deep grid. Confirm the id/label with `sipi describe-ui`. `sipi validate` and `run-test` reject a selector that is not exactly one of id / label / value |

## Build

| Problem | Solution |
|---------|----------|
| Build error | Check `/tmp/simpilot-build.log`: `grep -E "error:" /tmp/simpilot-build.log` |
| Signing error | Add `CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO` |
| Unknown scheme | `xcodebuild -list -project MyApp.xcodeproj` |
| SPM dependency resolution failed | `swift package resolve` |

## Execution

| Problem | Solution |
|---------|----------|
| Execution stalls midway | In a single ad-hoc Bash call, avoid `&&` chaining of `sipi` commands — one non-zero exit short-circuits the rest. Use `;` or `\|\|` so later commands still run. (Saved tests do not have this issue: `sipi run-test`/`run-suite` own the step loop.) |
| result.json missing | Verify that each test writes immediately upon completion |
| iPad launches slowly | iPhone `sleep 2` → iPad `sleep 4` |
| Section header uppercase | Use `grep -qi "pinned"` for case-insensitive matching |
| Dark Mode verify fails | Add `sleep 2-3` after changing the setting (iOS 18 applies it slowly) |
| System UI won't close | Try `ui_tap_label "<visible label>"` first. PhotosPicker multiple: `native_key 40` to confirm, `native_key 41` to cancel. FileImporter: `native_key 41`. ShareSheet: downward `sipi swipe` (or `native_swipe`). ColorPicker: touch the close button |
| `.borderless` Button fake success (iOS 26) | All tap methods give fake success for `.borderless` inside List. Workaround: remove `.borderless` or tap the entire row |
