# UI Test Patterns

Shared element-interaction reference for any skill that taps or inspects UI. Quirks, exceptions, and constraints follow the Quick Reference; per-iOS-version differences and the System-UI/PhotosPicker matrices are at the end.

## Element Interaction Fallback Chain

Check the Quick Reference below first — some controls (Toggle, Menu, DisclosureGroup) return "success" from tap but do not actually change state.

```
0. Check this file for the target control
   → If marked "false/fake success", skip to the method that works
1. ui_tap_label "Label"
   ↓ fail
2. ui_tap_id "identifier"
   ↓ fail
3. ui_tap_xy N N  (from frame: cx=x+w/2, cy=y+h/2)
   ↓ verify fail
4. Visual operation from screenshot:
   a. `ui_screenshot` → Read → determine position/state
   b. Execute action (touch / swipe / long press / clipboard paste)
   c. verify → if fail, mark FAIL
```

## Quick Reference

Legend: **Works** = confirmed working / **Fake success** = returns "successfully" but no state change / **-** = does not work or unsupported

| Target | `--label` | `--id` | `touch` | `swipe` | Correct approach |
|--------|-----------|--------|---------|---------|-----------------|
| Button | Works | Works | Works | - | Prefer `--label` |
| Button in List/Form | Works | Works | Works | - | `--label` or `--id` |
| Toggle | **Fake success** | **Fake success** | right edge -25pt | - | touch required (do not use `--label`/`--id`). `x = frame.x + frame.width - 25`, `y = frame.y + frame.height/2`. AXValue `"1"`=ON `"0"`=OFF |
| Stepper +/- | Works | Works | Works | - | Use `--id` or touch if unstable |
| Slider | - | - | - | drag within frame | `sipi slider $UDID --label "Name" --value N` (resolves, drags, verifies AXValue) |
| Segmented Picker | - | - | coordinate calc | - | `AXTabGroup` (no label; not `AXHeading`). `frame.x + (width/count)*(index+0.5)` |
| Menu (PopUpButton) | **Fake success** | **Fake success** | frame center | - | touch frame center → sleep 1-2s → select item with `--label`. **All methods fail inside List** |
| Picker (in Form) | Works | Works | - | - | Tap `"Title, Value"` → select option with `--label` |
| DatePicker | Works | Works | - | - | `"Date Picker"` → calendar → date `--label` |
| TextEditor | Works | Works | - | - | `.accessibilityLabel` required |
| DisclosureGroup | **Fake success** (iOS 18.x may work, iOS 26 fails) | **Works** | left edge x:30 | - | Prefer `--id`; touch left edge at x:30 if no id set. Children appear in describe-ui only when expanded |
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

For key combos and modifier keys, use `sipi key` / `sipi key-combo` (or `native_key`).

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

- Back: find back button frame with `ui_describe` → `ui_tap_xy` / `native_tap` (most reliable)
- `swipe-from-left-edge` may not work on iOS 18.1

### Modal / Sheet

- Sheet: can close with downward swipe. `.fullScreenCover`: requires a close button
- Sheet toolbar: not shown in describe-ui → tap by coordinate. iPad popover: calculate dynamically from frame

### Text Input

- Tap the field to focus it first, then type with `sipi type $UDID "text"` (the UDID comes first, then the text; quote text with spaces or newlines). US-keyboard characters are injected as HID key events; any text with accented letters, non-Latin scripts, or emoji automatically falls back to pasting via the simulator pasteboard (sipi saves and restores the prior pasteboard contents)
- Clear existing: select-all then delete via `sipi key-combo --modifiers 227 --key 4 $UDID` (Cmd+A, 227=Cmd 4=A) then `sipi key 42 $UDID` (Backspace)

### Scrolling

- Scroll with `native_swipe 0.5 0.7 0.5 0.3` (or `sipi swipe $UDID --norm --start-x 0.5 --start-y 0.7 --end-x 0.5 --end-y 0.3`)
- After scrolling, verify elements with `ui_describe` before tapping
- Return to top: swipe 2-3 times or tap status bar (y=20)

### Alert / Confirmation Dialog

- Confirm button labels with `describe-ui` → tap. Inside List: touch left edge (x: frame.x + 30)
- iPad popover: cannot tap button → dismiss with Escape (see constraints)
- **Destructive-confirm alerts** (e.g. a Trash/Delete button presenting a `UIAlertController`): the confirm button can be absorbed if tapped during the alert's presentation animation. After tapping the trigger, wait for the alert to settle before tapping confirm — use a conditional wait on the confirm label (or a brief `sleep 0.5`), then re-`describe-ui` and tap. (Observed live: a 確認 tap fired mid-animation and was dropped; re-describe + re-tap succeeded.)

### Pull-to-Refresh

`sipi swipe $UDID --norm --start-x 0.5 --start-y 0.35 --end-x 0.5 --end-y 0.9 --duration 1.0` (slow downward swipe; or `native_swipe 0.5 0.35 0.5 0.9`)

### Long Press

`sipi touch $UDID --norm -x N -y N --down --up --delay 1.5` (single long-press; `--delay` holds between down and up). A short hold may register as a regular tap.

### Deep Link

`xcrun simctl openurl $UDID 'scheme://path'`. First time shows a confirmation dialog → tap the "Open" button with `ui_tap_label "Open"` (label varies by locale, e.g., Japanese: "開く").

---

## Device Settings

Dark mode and Dynamic Type use `xcrun simctl ui $UDID appearance light|dark` and the Settings app (no native driver needed). For rotation, use `native_orientation portrait|landscape-left|landscape-right` (or `sipi orientation`). Wait `sleep 3` after rotation.

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
| Share Sheet | Separate process UI. Inspect with `ui_describe`; close with `ui_tap_label` on a visible label or downward `sipi swipe` (or `native_swipe`) |
| `.borderless` Button in List (iOS 26) | `tap --label`/`--id`/`touch` all give fake success. Workaround: remove `.borderless` or tap the entire row |
| Drag & Drop / Pinch / Rotation | touch supports down/up and basic swipe interpolation; complex multi-finger move is not supported |
| Menu in List (iOS 18.x) | List row absorbs gestures. All methods fail |
| iPad iOS 26 describe-ui | May return `DockFolderViewService` |
| iPad confirmationDialog | Cannot tap buttons inside popover |
| System UI (ASWebAuth, SFSafari) | Separate process. Use `ui_describe` / `ui_tap_label` — the native driver inspects and acts on this System UI in one tree |
| UIKit full-screen toolbar | Toolbar items in UIKit full-screen view controllers (e.g., photo viewer) are not exposed in describe-ui. Use screenshot + coordinate estimation |

### PhotosPicker Multiple Selection — Behavior by iOS Version

| Environment | Enter (confirm) | Esc (cancel) |
|---|---|---|
| iPhone iOS 18.4 | Stable (works repeatedly) | Works |
| iPhone iOS 18.6 | First time only | **Does not work** |
| iPhone iOS 26.x | First time only | Works |
| iPad iOS 26.x | Stable (works repeatedly) | Not verified (tap outside popover to close) |
