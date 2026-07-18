# Troubleshooting

## Setup

| Problem | Solution |
|---------|----------|
| `sipi: command not found` / `sipi doctor` fails | Install sipi (`curl -fsSL https://raw.githubusercontent.com/hmhv/SimPilot/main/install.sh \| bash`), or from a checkout run `swift build -c release` and set `SIPI` to `.build/release/sipi`. Run `sipi doctor` to confirm the core capabilities (CoreSimulator, SimulatorKit HID, AccessibilityPlatformTranslation) are present |
| install / `swift build` failure | `sudo xcode-select -s /Applications/Xcode.app`, verify with `xcodebuild -version` |
| Simulator not detected | `open -a Simulator` → `xcrun simctl boot "iPhone 16 Pro"` |
| Simulator unresponsive | `killall Simulator; sleep 2; open -a Simulator` |
| Insufficient disk space | Delete old runs, `xcrun simctl delete unavailable`, reduce keep-runs |

## Interaction & Detection

| Problem | Solution |
|---------|----------|
| tap has no effect / element not found | Check with `ui_describe` → use `ui_tap_id` or coordinates. Close any overlays first. Before a blind coordinate tap, confirm what is actually at the spot with `ui_describe_point` (`sipi describe-point --pixel`) |
| tap succeeds but no state change | Toggle/Menu/DisclosureGroup → use the correct method from `patterns.md` |
| Screenshot is black | Verify Booted state. Locked → `native_button home` (or `sipi button $UDID home`). Still launching → add sleep |
| App crashed | Check home screen with `ui_describe` → relaunch with `xcrun simctl launch $UDID $BUNDLE_ID` → mark the step FAIL |
| Keyboard not shown / type has no effect | Tap by coordinate to focus. Non-US characters via clipboard |
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
