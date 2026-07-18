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

A `--label`/`--id`/`--value` selector tap (and `sipi slider`) automatically re-fetches the **deep** grid tree and retries when the fast frontmost tree has no match, so selector taps reach System UI without you passing `--deep`. Only a *true* not-found escalates; a multiple-match or invalid-frame error fails immediately — for a multiple-match, follow the error's advice (add `--element-type`, use `--id`, or fall to coordinates), do not re-tap blindly. So fall through to coordinates (step 3) only when a selector genuinely cannot resolve. `--value` on `tap` is an exact-string match (distinct from `slider --value`, which is a 0…100 percentage). `--deep` on `describe-ui` is for inspection only.

## Quick Reference

Legend: **Works** = confirmed working / **Fake success** = returns "successfully" but no state change / **-** = does not work or unsupported

| Target | `--label` | `--id` | `touch` | `swipe` | Correct approach |
|--------|-----------|--------|---------|---------|-----------------|
| Button | Works | Works | Works | - | Prefer `--label` |
| Button in List/Form | Works | Works | Works | - | `--label` or `--id` |
| Toggle | Works (redirects to switch) | Works | width-31 inset (auto) | - | Prefer `--label` (optionally `--element-type Switch`). The resolver sibling-redirects a row label to its single switch, and when the resolved switch is wider than 100pt it taps the trailing inset (`x + width - 31`, centerY) for you. Only hand-compute a `touch` if no selector resolves; then `x = frame.x + frame.width - 31`, `y = frame.y + frame.height/2`. If a selector tap reports success but AXValue does not flip, fall back to that `touch`. AXValue `"1"`=ON `"0"`=OFF |
| Stepper +/- | Works | Works | Works | - | Use `--id` or touch if unstable |
| Slider | - | - | - | drag within frame | `sipi slider $UDID --label "Name" --value N` (resolves, drags, then polls AXValue; non-zero exit if it cannot reach the target). Add `--element-type Slider` to disambiguate and `--tolerance 0.02` (±2%, the default) to set the accepted band |
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

For single keys and modifier combos, use `sipi key` / `sipi key-combo` (or `native_key`); for an ordered burst of keycodes use `sipi key-sequence` (see below).

## Driving primitives (reach for these before computing coordinates by hand)

These first-class `sipi` commands are deterministic and usually beat hand-rolled coordinates. UDID comes first for all of them. Most are also expressible as saved v2 test actions (`long-press`, `slider`, `gesture`, `drag`, `key-combo`, `key-sequence`, `orientation`, `crown`) for `sipi-test` — see `../../sipi-test/references/json-reference.md`.

| Need | Command |
|------|---------|
| Scroll a view / system edge swipe | `sipi gesture scroll-down $UDID` — presets `scroll-up`/`scroll-down`/`scroll-left`/`scroll-right`, `swipe-from-{left,right,top,bottom}-edge` (`--duration` optional) |
| Precise reorder / handle / momentum drag | `sipi drag $UDID --start-x .. --start-y .. --end-x .. --end-y .. --steps 60` — interpolated touch-moves (`--steps` 1…1000, `--duration` default 0.6s); smoother than `swipe` |
| Identify what sits at a coordinate / debug a mis-tap | `sipi describe-point $UDID -x .. -y ..` — single hit-test (`--pixel`/`--norm`); returns a one-element array, or `[]` if nothing is hit |
| Disambiguate a label/value that matches >1 element | add `--element-type Button` / `--element-type Switch` / `--element-type Slider` to `tap`/`slider` (exact, case-sensitive describe-ui `type`, no `AX` prefix), e.g. `sipi tap $UDID --label "Notifications" --element-type Switch` |
| Pinch / zoom (2-finger) | two stateful calls: `sipi multitouch $UDID 1 x1 y1 x2 y2` (begin/move) then `sipi multitouch $UDID 2 x1' y1' x2' y2'` (end) — phase `1`=begin/move, `2`=end (`--norm` 0…1 default) |
| Apple Watch Digital Crown | `sipi crown $UDID <delta>` — sign sets direction (watchOS simulators only) |
| Ordered HID keycode burst | `sipi key-sequence --keycodes 11,8,15,15,18 $UDID` — each pressed+released in order (`--delay` default 0.1s) |

`describe-point` is the cheap way to confirm a computed coordinate (Toggle inset, Segmented Picker cell, headerless Tab Bar) actually lands on the intended element before a blind `touch`.

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
- Edge back-swipe: `sipi gesture swipe-from-left-edge $UDID` (may not work on iOS 18.1 — fall back to a back-button tap there)

### Modal / Sheet

- Sheet: can close with downward swipe. `.fullScreenCover`: requires a close button
- Sheet toolbar: not shown in describe-ui → tap by coordinate. iPad popover: calculate dynamically from frame

### Text Input

- Tap the field to focus it first, then type with `sipi type $UDID "text"` (the UDID comes first, then the text; quote text with spaces or newlines). By default the text is entered by pasting through the simulator pasteboard (Cmd+V), which is independent of the guest keyboard layout and input language — the reliable default. sipi saves and restores the prior pasteboard contents. Add `--keyboard` to inject US-keyboard HID key events instead (US-representable characters only; accented/non-Latin/emoji text is rejected in keyboard mode)
- Clear existing: select-all then delete via `sipi key-combo --modifiers 227 --key 4 $UDID` (Cmd+A, 227=Cmd 4=A) then `sipi key 42 $UDID` (Backspace)

### Scrolling

- Prefer the preset: `sipi gesture scroll-down $UDID` / `scroll-up` (also `scroll-left`/`scroll-right`). Use `native_swipe 0.5 0.7 0.5 0.3` (or `sipi swipe ...`) only when you need a precise start/end the preset cannot express
- System-edge gestures (back-swipe, Control Center, Notification Center): `sipi gesture swipe-from-left-edge $UDID` (and `swipe-from-{right,top,bottom}-edge`)
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

Dark mode and Dynamic Type use `xcrun simctl ui $UDID appearance light|dark` and the Settings app (no native driver needed). For rotation, use `native_orientation <portrait|portrait-upside-down|landscape-left|landscape-right|face-up|face-down>` (wraps `sipi orientation --set`). Wait `sleep 3` after rotation to let it settle, then optionally confirm it landed with `sipi orientation $UDID --json` (reads `{ orientation, raw }`).

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
| Drag & Drop (single finger / reorder / handle) | Use `sipi drag $UDID --steps 60` for interpolated touch-moves (1…1000 steps) — smoother and more reliable than `swipe` |
| Pinch / Rotation (2-finger) | `sipi multitouch` drives 2-finger phases (pinch/zoom directly; rotation is possible but manual — compute the rotated endpoints). Moves with more than 2 fingers are not supported |
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
