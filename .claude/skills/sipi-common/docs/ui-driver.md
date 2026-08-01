# UI Driver

Use this shell prelude at the top of every Bash call that inspects or taps simulator UI.
Shell state does not persist between Bash calls, so redefine `SIPI`, `UDID`, and these
functions each time.

Preflight resolves the `sipi` binary path once (see `preflight.md`) and prints a
ready-to-paste `SIPI=…` line. Copy that whole line **verbatim** as the first line below —
it is already shell-quoted (so a path with spaces, e.g. `~/My Projects/.build/release/sipi`,
works), so do NOT wrap it in quotes or re-run the resolver here. If preflight was not run in
this session, run its resolver first to get the line.

```bash
SIPI=/Users/you/.local/bin/sipi   # paste the SIPI= line preflight printed, verbatim (already shell-quoted; do not add quotes)
UDID="<resolved-udid>"
[ -x "$SIPI" ] || { echo "sipi not found at '$SIPI' — re-run preflight to resolve it" >&2; exit 1; }

ui_describe()   { "$SIPI" describe-ui "$UDID" "$@"; }
ui_tap_label()  { "$SIPI" tap "$UDID" --label "$1"; }
ui_tap_id()     { "$SIPI" tap "$UDID" --id "$1"; }
ui_tap_xy()     { "$SIPI" tap "$UDID" --pixel -x "$1" -y "$2"; }
ui_key()        { "$SIPI" key "$1" "$UDID"; }
ui_screenshot() { "$SIPI" screenshot "$UDID" "$1"; }

native_tap()         { "$SIPI" tap "$UDID" --norm -x "$1" -y "$2"; }
native_swipe()       { "$SIPI" swipe "$UDID" --norm --start-x "$1" --start-y "$2" --end-x "$3" --end-y "$4"; }
native_button()      { "$SIPI" button "$UDID" "$1"; }
native_key()         { "$SIPI" key "$1" "$UDID"; }
native_orientation() { "$SIPI" orientation "$UDID" --set "$1"; }
native_screenshot()  { "$SIPI" screenshot "$UDID" "$1"; }
native_type()        { "$SIPI" type "$UDID" "$1"; }
ui_set_text_id()     { "$SIPI" set-text "$UDID" "$2" --id "$1"; }      # write a field's AX value: no focus/keyboard/pasteboard, verified
native_drag()        { "$SIPI" drag "$UDID" --norm --start-x "$1" --start-y "$2" --end-x "$3" --end-y "$4"; }
native_gesture()     { "$SIPI" gesture "$1" "$UDID"; }   # preset: scroll-up/down/left/right, swipe-from-*-edge

ui_double_tap_label() { "$SIPI" double-tap "$UDID" --label "$1"; }
native_double_tap()   { "$SIPI" double-tap "$UDID" --norm -x "$1" -y "$2"; }
native_pinch()        { "$SIPI" pinch "$UDID" "$1" "${@:2}"; }   # direction: in (zoom out) | out (zoom in)

# Mechanical accessibility audit — no devicectl, works on any supported Xcode.
ui_a11y_audit()   { "$SIPI" a11y-audit "$UDID" "$@"; }           # --fast skips the deep grid pass; --rules, --min-touch-target, --fail-on

# Device state via devicectl (Xcode 27+). Read with no flag, write with one.
ui_biometrics()   { "$SIPI" biometrics "$UDID" "$@"; }           # status|enroll|unenroll|match|no-match (+ --json)
ui_appearance()   { "$SIPI" appearance "$UDID" "$@"; }           # no flags reads; --reduce-motion on, etc. writes
ui_voiceover()    { "$SIPI" voiceover "$UDID" "$@"; }            # no flags reads; --enable / --disable writes

# Frame-derived coordinates are logical points (pixel space) — use the --pixel wrappers, matching ui_tap_xy.
ui_touch_xy()        { "$SIPI" touch "$UDID" --pixel -x "$1" -y "$2" "${@:3}"; }              # add --down/--up/--delay as needed
ui_long_press_xy()   { "$SIPI" touch "$UDID" --pixel -x "$1" -y "$2" --down --up --delay "${3:-1.5}"; }
ui_describe_point()  { "$SIPI" describe-point "$UDID" --pixel -x "$1" -y "$2"; }
```

Use `ui_describe`, `ui_tap_label`, `ui_tap_id`, `ui_key`, and `ui_screenshot` as the default path. They drive the native `sipi` binary, which sees both the frontmost app tree and System UI (PhotosPicker, Share Sheet, SFSafariViewController). Pass `ui_describe --expect "Text"` when a subsequent grep is looking for specific text; this signals `sipi describe-ui` to auto-trigger its deeper grid pass when the fast frontmost tree does not contain the expected text.

Use `native_tap`, `native_swipe`, `native_drag`, `native_gesture`, `native_button`, `native_key`, `native_type`, `native_orientation`, or `native_screenshot` when a step already has normalized coordinates, needs high-throughput simulator input, or needs Simulator-only operations.

Use `ui_set_text_id <identifier> "<text>"` to put content into a text field when the typing itself is not what is being checked: it sets the element's accessibility value, so it needs no focus, no keyboard, and no pasteboard, handles any script, and fails loudly when the field did not accept the write. It is also the only text-entry path that still works on a simulator that has stopped delivering keyboard HID (including `type`'s Cmd+V paste) — a condition that follows device age, not the iOS version; see `troubleshooting.md`.

Use `native_pinch out` / `native_pinch in` for zoom gestures and `ui_double_tap_label` / `native_double_tap` for double-taps: both send the composed gesture the guest recognizes, which two separate `tap` calls or hand-assembled `multitouch` phases do not reliably produce. `native_pinch` accepts `--center-x/--center-y`, `--separation`, `--duration`, and `--steps`.

Use `ui_biometrics enroll` then `ui_biometrics match` (or `no-match`) to drive a Face ID / Touch ID prompt; matching does nothing while the device is unenrolled. `ui_appearance` reads or writes the accessibility appearance facets simctl cannot reach — reduce motion, reduce transparency, show borders, color filters, Liquid Glass opacity, Larger Accessibility Sizes. `ui_voiceover` reads or sets VoiceOver. These three need Xcode 27's simulator-capable devicectl and say so explicitly when it is unavailable; `ui_a11y_audit` does not, and works on any supported Xcode.

Use `ui_a11y_audit` for a mechanical accessibility pass over the current screen: undersized touch targets, unlabeled controls, ambiguous duplicate labels, meaningless labels, truncated text. Only `missing-label` is an error — it is decidable; the rest are warnings because they are inferences from the tree. Label rules cover DISABLED controls too (VoiceOver still announces them), while the touch-target rule does not (they cannot be tapped). It runs the deep grid pass by default (~1s per screen) so System UI and overlay elements are audited too — `--fast` skips it when only the app's own controls matter. It exits non-zero when an error-severity finding is present, so it can gate a check directly; add `--fail-on none` to inspect without failing, `--json` for structured output, `--rules` to run a subset, or `--min-touch-target` to change the 44pt threshold. An empty accessibility tree is a hard error rather than a clean report, so "no findings" always means the screen was actually inspected.

Use the `--pixel` helpers — `ui_touch_xy`, `ui_long_press_xy`, and `ui_describe_point` — with **frame-derived** coordinates (the logical points `describe-ui` reports in `frame`, the same space as `ui_tap_xy`). `ui_describe_point` returns a single-element array (or `[]` when nothing is hit) and `--pixel` is bounds-checked, so it errors cleanly instead of mis-targeting — use it to confirm a computed coordinate before a blind `ui_touch_xy`. (Do not feed frame-derived points to a `--norm` wrapper; the 0…1 bounds check will hard-error.)
