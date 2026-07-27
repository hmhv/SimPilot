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

# Frame-derived coordinates are logical points (pixel space) — use the --pixel wrappers, matching ui_tap_xy.
ui_touch_xy()        { "$SIPI" touch "$UDID" --pixel -x "$1" -y "$2" "${@:3}"; }              # add --down/--up/--delay as needed
ui_long_press_xy()   { "$SIPI" touch "$UDID" --pixel -x "$1" -y "$2" --down --up --delay "${3:-1.5}"; }
ui_describe_point()  { "$SIPI" describe-point "$UDID" --pixel -x "$1" -y "$2"; }
```

Use `ui_describe`, `ui_tap_label`, `ui_tap_id`, `ui_key`, and `ui_screenshot` as the default path. They drive the native `sipi` binary, which sees both the frontmost app tree and System UI (PhotosPicker, Share Sheet, SFSafariViewController). Pass `ui_describe --expect "Text"` when a subsequent grep is looking for specific text; this signals `sipi describe-ui` to auto-trigger its deeper grid pass when the fast frontmost tree does not contain the expected text.

Use `native_tap`, `native_swipe`, `native_drag`, `native_gesture`, `native_button`, `native_key`, `native_type`, `native_orientation`, or `native_screenshot` when a step already has normalized coordinates, needs high-throughput simulator input, or needs Simulator-only operations.

Use `ui_set_text_id <identifier> "<text>"` to put content into a text field when the typing itself is not what is being checked: it sets the element's accessibility value, so it needs no focus, no keyboard, and no pasteboard, handles any script, and fails loudly when the field did not accept the write. It is also the only text-entry path that works on iOS 27.0 simulators, where keyboard HID (including `type`'s Cmd+V paste) is not delivered at all.

Use the `--pixel` helpers — `ui_touch_xy`, `ui_long_press_xy`, and `ui_describe_point` — with **frame-derived** coordinates (the logical points `describe-ui` reports in `frame`, the same space as `ui_tap_xy`). `ui_describe_point` returns a single-element array (or `[]` when nothing is hit) and `--pixel` is bounds-checked, so it errors cleanly instead of mis-targeting — use it to confirm a computed coordinate before a blind `ui_touch_xy`. (Do not feed frame-derived points to a `--norm` wrapper; the 0…1 bounds check will hard-error.)
