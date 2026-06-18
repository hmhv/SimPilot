# UI Test Patterns

Reference for interaction patterns. Exceptions and constraints are listed at the end.

## Quick Reference

Legend: **Works** = confirmed working / **Fake success** = returns "successfully" but no state change / **-** = does not work or unsupported

| Target | `--label` | `--id` | `touch` | `swipe` | Correct approach |
|--------|-----------|--------|---------|---------|-----------------|
| Button | Works | Works | Works | - | Prefer `--label` |
| Button in List/Form | Works | Works | Works | - | `--label` or `--id` |
| Toggle | **Fake success** | **Fake success** | right edge -25pt | - | touch required. AXValue `"1"`=ON `"0"`=OFF |
| Stepper +/- | Works | Works | Works | - | Use `--id` or touch if unstable |
| Slider | - | - | - | drag within frame | `swipe --duration 2.0 --delta 2` |
| Segmented Picker | - | - | coordinate calc | - | `frame.x + width*(index+0.5)/count` |
| Menu (PopUpButton) | **Fake success** | **Fake success** | frame center | - | touch → sleep 1-2s → select with `--label`. **All methods fail inside List** |
| Picker (in Form) | Works | Works | - | - | Tap `"Title, Value"` → select option with `--label` |
| DatePicker | Works | Works | - | - | `"Date Picker"` → calendar → date `--label` |
| TextEditor | Works | Works | - | - | `.accessibilityLabel` required |
| DisclosureGroup | **Fake success** (iOS 18.x may work, iOS 26 fails) | **Works** | left edge x:30 | - | Prefer `--id`. Use left edge touch if no id set |
| Toolbar button | Works | Works | - | - | Different from Sheet toolbar |
| Sheet toolbar | - | - | coordinate | - | iPhone: Cancel~(50,105) Confirm~(375,105) |
| UIKit Toolbar (full-screen VC) | - | - | coordinate | - | Bottom bar not in describe-ui. Estimate from screenshot: Done~(30,848) Edit~(260,848) |
| Context Menu | - | - | down+1.5s+up | - | Long press required |
| Swipe Action | - | - | - | left/right swipe | Sleep 0.3 after swipe → `--label` |
| Search Bar | - | - | coordinate | - | No AXLabel. Paste via clipboard |
| Confirmation Dialog | Works | Works | Works | - | iPad popover has constraints |
| ColorPicker popup | - | - | right edge circle | - | Inspect with `ui_describe` if available. Touch color well to open, touch × to close |
| Tab Bar (AXRadioButton) | Works | - | Works | - | iOS 18.1-18.4, all iPad versions |
| Tab Bar (no children) | - | - | coordinate calc | - | iOS 18.6+/26 iPhone. Calculate from width/tab count |

For key combos and modifier keys, read the `axe` skill (see sipi-test/SKILL.md for location). If not available, tell the user and stop.

---

## Interaction Pattern Details

### App Launch

- Wait for launch with `sleep 2`. On iPad iOS 18.x the app may not come to the foreground → tap SpringBoard with `ui_tap_label "AppName"`
- iPad iOS 26: terminate+launch may return `DockFolderViewService` → do not terminate between tests when running suites

### Tab Switching

- **iOS 18.1-18.4**: `AXRadioButton` present → `ui_tap_label "TabName"`
- **iOS 18.6+ / iOS 26 (iPhone)**: no children → calculate coordinates from Tab Bar frame (width/tab count)
- **iPad**: `AXRadioButton` present in all versions → `--label` works
- 6+ tabs: last tab becomes "..." (More)
- Landscape iOS 26: use System Events via `osascript ... click (first radio button ... whose description is "TabName")`

### Navigation (push/pop)

- Back: find back button frame with `describe-ui` → `axe touch` (most reliable)
- `swipe-from-left-edge` may not work on iOS 18.1

### Modal / Sheet

- Sheet: can close with downward swipe. `.fullScreenCover`: requires a close button
- Sheet toolbar: not shown in describe-ui → tap by coordinate. iPad popover: calculate dynamically from frame

### Text Input

- Paste via clipboard (`<<<` adds a newline, so avoid it). Read the `axe` skill for commands (see sipi-test/SKILL.md for location). If not available, tell the user and stop
- Clear existing: Cmd+A + Backspace

### Scrolling

- If `axe gesture scroll-down` does not work → `axe swipe --start-x 200 --start-y 700 --end-x 200 --end-y 200`
- After scrolling, verify elements with `describe-ui` before tapping
- Return to top: swipe 2-3 times or tap status bar (y=20)

### Toggle

Do not use `--label`/`--id`. Get frame → `x = frame.x + frame.width - 25`, `y = frame.y + frame.height / 2` → `axe touch --down --up`

### Segmented Picker

`AXTabGroup` (no label). Coordinate: `frame.x + (width/count) * (index + 0.5)`. Do not confuse with `AXHeading`.

### Menu

touch the frame center → sleep 1-2s → `--label` for item inside menu. **All methods fail inside a List (see constraints).**

### DisclosureGroup

`--label` gives fake success. Prefer `--id`; if not set, touch left edge at x:30. Children only appear in describe-ui when expanded.

### Alert / Confirmation Dialog

- Confirm button labels with `describe-ui` → tap. Inside List: touch left edge (x: frame.x + 30)
- iPad popover: cannot tap button → dismiss with Escape (see constraints)

### Pull-to-Refresh

`axe swipe --start-x 200 --start-y 300 --end-x 200 --end-y 800 --duration 3.0 --delta 2`

### Long Press

`axe touch --down` → `sleep 1.5` → `axe touch --up`. Short `--delay` may register as a regular tap.

### Deep Link

`xcrun simctl openurl $UDID 'scheme://path'`. First time shows a confirmation dialog → tap the "Open" button with `ui_tap_label "Open"` (label varies by locale, e.g., Japanese: "開く").

---

## Device Settings

For dark mode, Dynamic Type, landscape, and other commands, read the `axe` skill (see sipi-test/SKILL.md for location). If not available, tell the user and stop. Use `native_orientation portrait|landscape-left|landscape-right` for rotation when the native bridge is available; wait `sleep 3` after rotation.

---

## iOS Version Differences (Key Points)

| Component | iOS 18.x | iOS 26 |
|---|---|---|
| Tab bar (iPhone) | 18.1-18.4: `AXRadioButton` present. 18.6+: no children | Floating, no labels → use coordinates |
| Tab bar (iPad) | Displayed at top, `AXRadioButton` present | Displayed at top, `AXRadioButton` present |
| DisclosureGroup | Can expand with `--label` | `--label` fails → use `--id` or left edge touch |
| Context Menu | Long press 1.0-1.5s | Same |
| Search bar (iPad) | `AXButton "Search"` → tap to expand | `AXSearchField` shown directly |
| Search bar close (iPhone) | "Cancel" | "Close" |

---

## Constraints

| Pattern | Reason |
|---|---|
| Tab Badge (.badge()) | No tab bar children on iOS 18.6+/26 |
| Keyboard show/hide | No keyboard information in describe-ui |
| PhotosPicker (single selection) | Separate process UI. Photo grid is touchable; tap immediately dismisses. Cancel with `ui_key 41` (Esc) |
| PhotosPicker (multiple selection) | Separate process UI. Photo grid is touchable; confirm with `ui_key 40` (Enter), cancel with `ui_key 41` (Esc). Stability varies by iOS version (see below) |
| FileImporter | Separate process UI. Inspect with `ui_describe`; if controls are not stable, close with `ui_key 41` (Esc) |
| Share Sheet | Separate process UI. Inspect with `ui_describe`; close with `ui_tap_label` on a visible label or downward `axe swipe` |
| `.borderless` Button in List (iOS 26) | `tap --label`/`--id`/`touch` all give fake success. Workaround: remove `.borderless` or tap the entire row |
| Drag & Drop / Pinch / Rotation | axe touch only supports down/up; move is not supported |
| Menu in List (iOS 18.x) | List row absorbs gestures. All methods fail |
| iPad iOS 26 describe-ui | May return `DockFolderViewService` |
| iPad confirmationDialog | Cannot tap buttons inside popover |
| System UI (ASWebAuth, SFSafari) | Separate process. Use `ui_describe` / `ui_tap_label` so native fallback can inspect and act when AXe is blind |
| UIKit full-screen toolbar | Toolbar items in UIKit full-screen view controllers (e.g., photo viewer) are not exposed in describe-ui. Use screenshot + coordinate estimation |

### PhotosPicker Multiple Selection — Behavior by iOS Version

| Environment | Enter (confirm) | Esc (cancel) |
|---|---|---|
| iPhone iOS 18.4 | Stable (works repeatedly) | Works |
| iPhone iOS 18.6 | First time only | **Does not work** |
| iPhone iOS 26.x | First time only | Works |
| iPad iOS 26.x | Stable (works repeatedly) | Not verified (tap outside popover to close) |
