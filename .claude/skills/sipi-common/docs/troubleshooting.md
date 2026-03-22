# Troubleshooting

## Setup

| Problem | Solution |
|---------|----------|
| `axe: command not found` | `brew install cameroncooke/axe/axe` → `axe init` |
| make install build failure | `sudo xcode-select -s /Applications/Xcode.app`, verify with `xcodebuild -version` |
| Simulator not detected | `open -a Simulator` → `xcrun simctl boot "iPhone 16 Pro"` |
| Simulator unresponsive | `killall Simulator; sleep 2; open -a Simulator` |
| Insufficient disk space | Delete old runs, `xcrun simctl delete unavailable`, reduce keep-runs |

## Interaction & Detection

| Problem | Solution |
|---------|----------|
| tap has no effect / element not found | Check with describe-ui → use `--id` or coordinates. Close any overlays first |
| tap succeeds but no state change | Toggle/Menu/DisclosureGroup → use the correct method from `../../sipi-test/docs/patterns.md` |
| Screenshot is black | Verify Booted state. Locked → `axe button home`. Still launching → add sleep |
| App crashed | Check home screen with describe-ui → restart with `launch` → mark the step FAIL |
| Keyboard not shown / type has no effect | Tap by coordinate to focus. Non-US characters via clipboard |
| Cannot interact with alert | Verify labels with describe-ui. Add sleep 0.5. Fall back to coordinates if not visible |
| Scroll position off | Use `axe swipe` to control amount. Verify with describe-ui after scrolling |
| hints failing every time | Check that environment variants (device-class / device-name / ios / orientation) are correct. Update to a stronger method on success |

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
| Execution stalls midway | `&&` chaining is prohibited (see `../../sipi-test/docs/run.md`). Use `;` or `\|\|` |
| result.json missing | Verify that each test writes immediately upon completion |
| iPad launches slowly | iPhone `sleep 2` → iPad `sleep 4` |
| Section header uppercase | Use `grep -qi "pinned"` for case-insensitive matching |
| Dark Mode verify fails | Add `sleep 2-3` after changing the setting (iOS 18 applies it slowly) |
| System UI won't close | PhotosPicker single: `touch` to dismiss immediately. Multiple: `key 40` (Enter) to confirm, `key 41` (Esc) to cancel. Stability varies by iOS version (see `../../sipi-test/docs/patterns.md`). FileImporter: `key 41`. ShareSheet: downward `swipe`. ColorPicker: `touch` the × |
| `.borderless` Button fake success (iOS 26) | All tap methods give fake success for `.borderless` inside List. Workaround: remove `.borderless` or tap the entire row |
