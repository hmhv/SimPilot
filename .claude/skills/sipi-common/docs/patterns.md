# UI Interaction Patterns

Which control behaves how, and what to do when it misbehaves — plus
§ App State on Disk, for reading back what the app persisted. For *which command
does what*, see `ui-driver.md`; the same primitives are available as saved v2 test
actions (`../../sipi-test/references/actions.md`).

## Element Interaction Fallback Chain

Check the Quick Reference first — some controls (Toggle, Menu, DisclosureGroup)
return success from a tap without changing state.

```
0. Look up the control below
   → marked "fake success"? skip to the method that works
1. sipi tap $UDID --label "Label"
   ↓ fail
2. sipi tap $UDID --id "identifier"
   ↓ fail
3. sipi tap $UDID --pixel -x cx -y cy   (from frame: cx=x+w/2, cy=y+h/2)
   ↓ verify fail
4. Screenshot → Read → locate → touch / swipe / long press → verify → else FAIL
```

A `--label` / `--id` / `--value` tap (and `sipi slider`) re-fetches the deep grid
tree and retries automatically when the fast tree has no match, so selector taps
reach System UI without `--deep`. Only a *true* not-found escalates: a
multiple-match or invalid-frame error fails immediately. On a multiple-match,
follow the error's advice (`--element-type`, `--id`, or coordinates) rather than
re-tapping. Fall through to coordinates only when a selector genuinely cannot
resolve.

`--value` on `tap` is an exact-string match, distinct from `slider --value`,
which is a 0…100 percentage.

## Quick Reference

**Works** = confirmed / **Fake** = reports success, no state change / **-** = not supported

| Target | `--label` | `--id` | `touch` | `swipe` | Correct approach |
|--------|-----------|--------|---------|---------|-----------------|
| Button | Works | Works | Works | - | Prefer `--label` |
| Button in List/Form | Works | Works | Works | - | `--label` or `--id` |
| Toggle | Works | Works | inset (auto) | - | Prefer `--label` — see note A |
| Stepper +/- | Works | Works | Works | - | `--id`, or touch if unstable |
| Slider | - | - | - | drag in frame | `sipi slider $UDID --label "Name" --value N` — note B |
| Segmented Picker | - | - | computed | - | `AXTabGroup`; `frame.x + (width/count)*(index+0.5)` |
| Menu (PopUpButton) | **Fake** | **Fake** | frame center | - | Touch center → wait 1-2s → pick item by `--label`. All methods fail inside List |
| Picker (in Form) | Works | Works | - | - | Tap `"Title, Value"` → pick option by `--label` |
| DatePicker | Works | Works | - | - | `"Date Picker"` → calendar → date by `--label` |
| TextEditor | Works | Works | - | - | `.accessibilityLabel` required |
| DisclosureGroup | **Fake** | Works | left edge x:30 | - | Prefer `--id` — see note C |
| Toolbar button | Works | Works | - | - | Different from Sheet toolbar |
| Sheet toolbar | - | - | coordinate | - | iPhone: Cancel ~(50,105), Confirm ~(375,105) |
| UIKit toolbar (full-screen VC) | - | - | coordinate | - | Not in describe-ui; estimate from screenshot |
| Context Menu | - | - | down+1.5s+up | - | Long press required |
| Swipe Action | - | - | - | left/right | Wait 0.3s after the swipe, then `--label` |
| Search Bar | - | - | coordinate | - | No AXLabel |
| Confirmation Dialog | Works | Works | Works | - | iPad popover has constraints |
| ColorPicker popup | - | - | right edge circle | - | Touch the color well to open, × to close |
| Tab Bar (AXRadioButton) | Works | - | Works | - | iOS 18.1-18.4, all iPad versions |
| Tab Bar (no children) | - | - | computed | - | iOS 18.6+ iPhone; from width / tab count |

**A — Toggle.** The resolver sibling-redirects a row label to its single switch,
and when that switch is wider than 100pt it taps the trailing inset
(`x + width - 31`, centerY) for you. Add `--element-type Switch` to disambiguate.
Hand-compute a touch only if no selector resolves, or if a selector reports
success but AXValue does not flip: `x = frame.x + frame.width - 31`,
`y = frame.y + frame.height/2`. AXValue `"1"` = ON, `"0"` = OFF.

**B — Slider.** `sipi slider` resolves the element, drags the thumb, then polls
AXValue, exiting non-zero if it cannot reach the target. `--element-type Slider`
disambiguates; `--tolerance 0.02` (±2%, the default) sets the accepted band.

**C — DisclosureGroup.** `--label` may work on iOS 18.x but fails on iOS 26+.
Touch the left edge at x:30 when no id is set. Children appear in `describe-ui`
only while expanded.

---

## Interaction Details

### App Launch

- Wait ~2s after launch. On iPad iOS 18.x the app may not come forward — tap it
  on SpringBoard with `sipi tap $UDID --label "AppName"`.
- iPad iOS 26+: terminate+launch may return `DockFolderViewService`. Do not
  terminate between tests when running suites.

### Tab Switching

- iOS 18.1-18.4: `AXRadioButton` present → tap by `--label`.
- iOS 18.6+ / iOS 26+ iPhone: no children → compute coordinates from the tab bar
  frame (width / tab count).
- iPad: `AXRadioButton` present in all versions → `--label` works.
- 6+ tabs: the last becomes "..." (More).
- Landscape iOS 26+: use System Events —
  `osascript ... click (first radio button ... whose description is "TabName")`.

### Navigation (push/pop)

- Back: read the back button's frame with `describe-ui`, then tap by coordinate
  (most reliable).
- Edge back-swipe: `sipi gesture swipe-from-left-edge $UDID`. May not work on
  iOS 18.1 — fall back to the back button there.

### Modal / Sheet

- A sheet closes with a downward swipe; `.fullScreenCover` needs its close button.
- Sheet toolbars are not in `describe-ui` → tap by coordinate. For an iPad
  popover, compute from the frame.

### Text Input

**Default: `sipi set-text $UDID "text" --id <identifier>`.** It writes the
element's accessibility value, so it needs no focus, no keyboard, and no
pasteboard; it takes any script (Japanese, emoji), replaces the whole value, and
verifies the write against the app instead of reporting a silent success. The
field must be on screen — it is hit-tested like a tap, so scroll it into view
first.

Two fields cannot self-verify and need `--no-verify` plus an assertion on the
app's own output: a secure field (reads back as bullets) and an empty write
(reports its placeholder).

Use `sipi type` only when the KEYSTROKES are the subject — per-character
`onChange`, keyboard toolbar, candidate bar, Return/submit. Tap the field to
focus it first, then `sipi type $UDID "text"`. It pastes via the pasteboard by
default; `--keyboard` injects US-only keystrokes and `--clear` selects-all and
deletes first. Because `set-text` types nothing, it also does not exercise input
filters — a length cap or character whitelist may be bypassed (unmeasured).

`type` has three measured failure modes — a simulator that has stopped accepting
keyboard HID, the guest keyboard layout deciding what `--keyboard` actually types
(and IME composition under a non-Latin keyboard), and `--clear` against a pending
composition. All three, with their recovery steps — including the Xcode 27
service `type` falls back to when its own keystrokes do not arrive — are in
`troubleshooting.md`.

### Scrolling

- Prefer the preset: `sipi gesture scroll-down $UDID` (also `scroll-up`,
  `scroll-left`, `scroll-right`). Use `sipi swipe` only for a precise start/end
  the preset cannot express.
- System-edge gestures (back-swipe, Control Center, Notification Center):
  `sipi gesture swipe-from-{left,right,top,bottom}-edge $UDID`.
- Re-read with `describe-ui` after scrolling, before tapping.
- Return to top: swipe 2-3 times, or tap the status bar (y=20).

### Alert / Confirmation Dialog

- Confirm the button labels with `describe-ui`, then tap. Inside a List, touch
  the left edge (`frame.x + 30`).
- iPad popover: buttons cannot be tapped — dismiss with Escape.
- **Destructive-confirm alerts** (a Delete button presenting a
  `UIAlertController`): the confirm tap is absorbed if it fires during the
  presentation animation. After tapping the trigger, wait for the alert to settle
  — `sipi wait-for "$UDID" --label 確認 --element-type Button`, or ~0.5s — then
  re-read and tap.
  (Observed live: a 確認 tap fired mid-animation and was dropped; re-describe +
  re-tap succeeded.)

### Pull-to-Refresh

`sipi swipe $UDID --norm --start-x 0.5 --start-y 0.35 --end-x 0.5 --end-y 0.9 --duration 1.0`
— a slow downward swipe.

### Deep Link

`xcrun simctl openurl $UDID 'scheme://path'`. The first use shows a confirmation
dialog → tap "Open" (localized, e.g. Japanese「開く」).

### Home Screen Widgets

Measured on iOS 27.0 (iPhone 17, Japanese locale). iOS 18.x and 26 were not
measured — re-read the tree before relying on these labels.

**Add.** Long press an empty spot to enter jiggle mode, then work the edit menu:

```bash
sipi touch "$UDID" --pixel -x 201 -y 650 --down --up --delay 1.5   # jiggle mode
sipi tap "$UDID" --label 編集                                      # → menu
sipi tap "$UDID" --label ウィジェットを追加                        # → gallery sheet
```

Tap the menu item in the same step that opened the menu. The 編集 menu is
transient: with a tree read and a few seconds in between, it had dismissed
itself and the tap found nothing.

The gallery lists one `Button` per app under
`Group id="add-sheet-collection-view"`, so `--label "カレンダー"` works there.
Filter it by writing the search field through its placeholder:

```bash
sipi set-text "$UDID" "カレンダー" --value "ウィジェットを検索"
```

Then branch on the tree, because the filtered sheet has two shapes:

| Tree after the search | Result rows | How to open one |
|---|---|---|
| `add-sheet-collection-view` still present | Ordinary `Button`s | `tap --label "<AppName>"` |
| Field in its editing presentation (`Button "閉じる"` beside it, no collection group) | **Not in the tree** | Screenshot → locate the row → `tap --pixel` |

In the second shape nothing recovers the rows — a 10s `wait-for --label` and a
`describe-point` on the row's own coordinates both came back empty — but the row
is still hit-testable, and `tap --pixel` opened it.

The detail sheet holds the size carousel:

```
Button "カレンダー, 次はこちら" value="ウィジェット, 小" frame=(119,435,164,164)
Slider value="全8ページ中の1ページ目" frame=(24,735,354,31)
Button " ウィジェットを追加" frame=(24,766,354,50)
```

Page the carousel with `sipi drag --pixel … --steps 40` across the preview; a
plain `swipe` over the preview left it on page 1. The selected size is the preview button's
AXValue (`ウィジェット, 小` / `中` / `大`), the position is the unnamed `Slider`
— re-read once the animation settles, since a mid-animation read can be missing
the preview button. `tap --label "ウィジェットを追加"` then adds it; the real
label starts with a space, which the selector trims (see § Constraints).

**Remove or resize.** Long press the widget itself. Its context menu carries
stable ids, so no label matching is needed:

| Item | id |
|---|---|
| ウィジェットを編集 | `com.apple.springboardhome.application-shortcut-item.configure-widget` |
| ホーム画面を編集 | `com.apple.springboardhome.application-shortcut-item.rearrange-icons` |
| ウィジェットを削除 | `com.apple.springboardhome.application-shortcut-item.remove-widget` |

The same menu has a size row (`アプリアイコン`, `小型のウィジェット` …
`特大（縦向き）のウィジェット`) that morphs the widget in place. `remove-widget`
raises a confirmation alert → `tap --label 削除`.

**Pages.** `Slider id="spotlight-pill"` reports the current page in its AXValue
(`全2ページ中の1ページ目`). Two things about paging:

- **A horizontal page swipe must not cross a widget.** A swipe at `y=184`, the
  vertical center of a widget, launched that widget's app (Maps, straight into
  its location-permission alert) instead of paging. Pick a `y` no widget covers
  — the empty band below the icon rows (`y=650` here) paged reliably.
- Right after a page change the previous page's items are still in the tree,
  reported off screen with a negative `x` — `"onscreen": false` in the JSON
  form, the bare token `offscreen` in `--format compact`, and absent altogether
  when the runtime does not report it. Re-read once it settles, and drop those
  before treating what you see as the current page.

Jiggle mode changes two things a selector may depend on: every icon and widget
becomes a `GenericElement` instead of a `Button` (so `--element-type Button`
stops matching), and `spotlight-pill` counts one extra page for the empty
trailing page (`全2ページ` → `全3ページ`).

An inventory therefore means paging through and reading every page. Widgets are
the elements whose AXValue starts with `ウィジェット` (`ウィジェット`,
`ウィジェット, スタック`).

---

## Device Settings

Light/dark and Dynamic Type go through `xcrun simctl ui $UDID appearance
light|dark` and `content_size`; no native driver needed. The accessibility facets
simctl cannot reach — reduce motion, reduce transparency, show borders, color
filters, Liquid Glass opacity, Larger Accessibility Sizes — go through
`sipi appearance` (Xcode 27+). VoiceOver cannot be switched on: that is retired,
since on iOS 27 turning it back off empties the accessibility tree of every app
launched afterwards until the device restarts. `sipi voiceover "$UDID"` still reads the state.

For rotation, `sipi orientation $UDID --set <portrait|portrait-upside-down|landscape-left|landscape-right|face-up|face-down>`.
Wait ~3s for it to settle, then confirm. The plain read
(`sipi orientation $UDID --json`) reports only the four upright orientations —
SimulatorKit cannot express the flat ones — so confirm a `face-up` / `face-down`
set with `--physical`, which adds `flat`, `physical`, and `locked` from devicectl.

---

## App State on Disk

A verification often ends at a file inside the app's container or an App Group —
what the app actually persisted. `sipi container inspect` is the reader:

```bash
sipi container inspect "$UDID" com.example.app --group group.com.example \
  Library/Preferences/group.com.example.plist \
  --format plist --key-path '$.lastSyncedAt'
```

**Never read a number with PlistBuddy.** `PlistBuddy -c Print` formats reals
with `%f` — six decimals — and destroys the value silently. Measured on the same
plist: `2.5e-08` prints as `0.000000`, a stored value that reads as zero, and
`1234.5678901234567` prints as `1234.567871`. `container inspect --format plist`
and `plutil -p` both report what is stored.

**The file lags the app.** `UserDefaults` writes go to cfprefsd, not to disk.
Measured on iOS 27 with a process writing two keys and no `synchronize()`: the
plist held 0 of 2 keys immediately after the write and both within 6s, and a
second run read 1 of 2 keys at ~1s — a partial state indistinguishable from the
app failing to save that field. Two ways out:

- Read the logical value instead —
  `xcrun simctl spawn "$UDID" defaults read <suite>` was already correct at t=0.
- Or terminate the app first (`xcrun simctl terminate "$UDID" <bundle-id>`) and
  then read the file.

**Do not `rm` a preferences plist to reset it.** With the domain still cached by
cfprefsd, a deleted `Library/Preferences/<suite>.plist` was never recreated —
observed for 148s, including after the writing process exited — so every file
read reports the file missing while the values are still live. Reset the domain
with `xcrun simctl spawn "$UDID" defaults delete <suite>`.

---

## iOS Version Differences

Measured on iOS 18.x and iOS 26. iOS 27 was not separately measured for these UI
behaviors; treat the iOS 26+ column as the expected baseline and re-check with
`describe-ui` before relying on it.

| Component | iOS 18.x | iOS 26+ |
|---|---|---|
| Tab bar (iPhone) | 18.1-18.4: `AXRadioButton`. 18.6+: no children | Floating, no labels → coordinates |
| Tab bar (iPad) | Top, `AXRadioButton` | Top, `AXRadioButton` |
| DisclosureGroup | Expands with `--label` | `--label` fails → `--id` or left-edge touch |
| Context Menu | Long press 1.0-1.5s | Same |
| Search bar (iPad) | `AXButton "Search"` → tap to expand | `AXSearchField` shown directly |
| Search bar close (iPhone) | "Cancel" | "Close" |

---

## Constraints

| Pattern | Reason |
|---|---|
| Tab Badge (`.badge()`) | No tab bar children on iOS 18.6+ / 26+ |
| Keyboard show/hide | Keyboard state is not in describe-ui |
| PhotosPicker (single) | Separate process. Grid is touchable; a tap dismisses immediately. Cancel with Esc (`sipi key 41 $UDID`) |
| PhotosPicker (multiple) | Separate process. Confirm with Enter (`sipi key 40 $UDID`), cancel with Esc. Stability varies by version — see below |
| FileImporter | Separate process. Inspect with `describe-ui`; close with Esc if controls are unstable |
| Share Sheet | Separate process. Close by tapping a visible label, or a downward `sipi swipe` |
| `.borderless` Button in List (iOS 26+) | `--label` / `--id` / `touch` all give fake success. Remove `.borderless`, or tap the whole row |
| Drag & drop / reorder | Use `sipi drag --steps 60`; smoother than `swipe` |
| Rotation gesture (2-finger) | Not a preset. Assemble from `sipi multitouch` phases with per-step rotated endpoints. More than 2 fingers is unsupported |
| Menu in List (iOS 18.x) | The row absorbs the gesture. All methods fail |
| iPad iOS 26+ describe-ui | May return `DockFolderViewService` |
| iPad confirmationDialog | Buttons inside the popover cannot be tapped |
| System UI (ASWebAuth, SFSafari) | Separate process, but the native driver inspects and acts on it in one tree |
| UIKit full-screen toolbar | Not exposed in describe-ui. Screenshot + coordinate estimation |
| Widget gallery search results | In the field's editing presentation the filtered rows leave the AX tree; the rows stay hit-testable — screenshot + `tap --pixel`. See § Home Screen Widgets |
| Whitespace-only AXLabel | Trims to empty, so `--label` / `--value` cannot name it. Use `--id` or a coordinate — see below |

### Labels with whitespace

Every selector (`--label`, `--id`, `--value`) trims
`.whitespacesAndNewlines` from both the query and the tree value, so a label
that merely starts or ends with a space needs no special handling: the Home
Screen's real `Button " ウィジェットを追加"` matches
`--label "ウィジェットを追加"`. Copying the label out of `describe-ui` verbatim
is still the safer habit, since the padding is invisible in the output.

What cannot be selected is a label that is *entirely* whitespace — it trims to
empty and no selector can name it. They exist: SpringBoard's own application
element is labelled `" "`, and the Japanese keyboard exposes `"　"`
(full-width space) and `"\n"` (Return). Reach those with `--id` or a coordinate.

### PhotosPicker multiple selection, by version

| Environment | Enter (confirm) | Esc (cancel) |
|---|---|---|
| iPhone iOS 18.4 | Stable | Works |
| iPhone iOS 18.6 | First time only | **Does not work** |
| iPhone iOS 26.x | First time only | Works |
| iPad iOS 26.x | Stable | Not verified — tap outside the popover |
