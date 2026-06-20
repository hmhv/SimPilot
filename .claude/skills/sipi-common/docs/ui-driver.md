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
```

Use `ui_describe`, `ui_tap_label`, `ui_tap_id`, `ui_key`, and `ui_screenshot` as the default path. They drive the native `sipi` binary, which sees both the frontmost app tree and System UI (PhotosPicker, Share Sheet, SFSafariViewController). Pass `ui_describe --expect "Text"` when a subsequent grep is looking for specific text; this signals `sipi describe-ui` to auto-trigger its deeper grid pass when the fast frontmost tree does not contain the expected text.

Use `native_tap`, `native_swipe`, `native_button`, `native_key`, `native_orientation`, or `native_screenshot` when a step already has normalized coordinates, needs high-throughput simulator input, or needs Simulator-only operations.
