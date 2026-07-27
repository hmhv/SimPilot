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
| `type` reports `ok` but NOTHING is entered, on an iOS 27.0 simulator | Verified on Xcode 27.0 beta 4 (27A5228h): HID **keyboard** delivery is dead on the iOS 27.0 runtime — Cmd+V (the default paste path), `--keyboard`, and bare `sipi key 42` all no-op, while taps/swipes/buttons work. The same binary types fine on an iOS 26.4 device. **Use `sipi set-text $UDID "text" --id <id>`** (or the `set-text` test action), which writes the field's accessibility value and needs no keyboard at all; it is verified against the app, so it fails loudly instead of pretending. `--clear` is no help here — Cmd+A and delete are keyboard HID too, so it is equally dead on iOS 27.0; `set-text` needs no clear because it replaces the whole value. Do not treat this as an app bug |
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
