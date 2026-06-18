# UI Driver

Use this shell prelude at the top of every Bash call that inspects or taps simulator UI.
Shell state does not persist between Bash calls, so redefine `UDID` and these functions each time.

```bash
UDID="${UDID:?set UDID}"

resolve_sipilot_root() {
  if [ -n "${SIPILOT_ROOT:-}" ] && [ -d "$SIPILOT_ROOT" ]; then
    printf '%s\n' "$SIPILOT_ROOT"
    return
  fi
  for root in \
    "$PWD" \
    "$(cd "$PWD/.." 2>/dev/null && pwd)" \
    "$(cd "$PWD/../.." 2>/dev/null && pwd)" \
    "$PWD/SimPilot" \
    "$HOME/Documents/github/SimPilot"
  do
    if [ -x "$root/NativePrototype/Scripts/sipi-ui" ]; then
      printf '%s\n' "$root"
      return
    fi
  done
  printf '%s\n' ""
}

SIPILOT_ROOT="$(resolve_sipilot_root)"
SIPI_UI=""
SIPI_BRIDGE=""
if [ -n "$SIPILOT_ROOT" ]; then
  SIPI_UI="$SIPILOT_ROOT/NativePrototype/Scripts/sipi-ui"
  SIPI_BRIDGE="$SIPILOT_ROOT/NativePrototype/.build/debug/sipi-bridge"
  if [ -x "$SIPI_UI" ] && [ ! -x "$SIPI_BRIDGE" ]; then
    (cd "$SIPILOT_ROOT/NativePrototype" && swift build >/dev/null)
  fi
  export SIPI_BRIDGE
fi

ui_describe() {
  if [ -x "$SIPI_UI" ]; then
    "$SIPI_UI" describe "$UDID" "$@"
  else
    axe describe-ui --udid "$UDID"
  fi
}

ui_tap_label() {
  if [ -x "$SIPI_UI" ]; then
    "$SIPI_UI" tap "$UDID" --label "$1"
  else
    axe tap --label "$1" --udid "$UDID"
  fi
}

ui_tap_id() {
  if [ -x "$SIPI_UI" ]; then
    "$SIPI_UI" tap "$UDID" --id "$1"
  else
    axe tap --id "$1" --udid "$UDID"
  fi
}

ui_tap_xy() {
  if [ -x "$SIPI_UI" ]; then
    "$SIPI_UI" tap "$UDID" -x "$1" -y "$2"
  else
    axe tap -x "$1" -y "$2" --udid "$UDID"
  fi
}

ui_key() {
  if [ -x "$SIPI_BRIDGE" ]; then
    "$SIPI_BRIDGE" key "$UDID" "$1"
  else
    axe key "$1" --udid "$UDID"
  fi
}

ui_screenshot() {
  if [ -x "$SIPI_BRIDGE" ]; then
    "$SIPI_BRIDGE" screenshot "$UDID" "$1"
  else
    axe screenshot --udid "$UDID" --output "$1"
  fi
}

native_tap() {
  [ -x "$SIPI_BRIDGE" ] || return 127
  "$SIPI_BRIDGE" tap "$UDID" "$1" "$2"
}

native_swipe() {
  [ -x "$SIPI_BRIDGE" ] || return 127
  "$SIPI_BRIDGE" swipe "$UDID" "$1" "$2" "$3" "$4"
}

native_button() {
  [ -x "$SIPI_BRIDGE" ] || return 127
  "$SIPI_BRIDGE" button "$UDID" "$1"
}

native_key() {
  [ -x "$SIPI_BRIDGE" ] || return 127
  "$SIPI_BRIDGE" key "$UDID" "$1"
}

native_orientation() {
  [ -x "$SIPI_BRIDGE" ] || return 127
  "$SIPI_BRIDGE" orientation "$UDID" "$1"
}

native_screenshot() {
  [ -x "$SIPI_BRIDGE" ] || return 127
  "$SIPI_BRIDGE" screenshot "$UDID" "$1"
}
```

Use `ui_describe`, `ui_tap_label`, `ui_tap_id`, `ui_key`, and `ui_screenshot` as the default path. They use AXe first where useful and use the native bridge when it is available or needed for System UI. Pass `ui_describe --expect "Text"` when a subsequent grep is looking for specific text; this lets the driver fall back to native AX when AXe returns a partial tree.

Use `native_tap`, `native_swipe`, `native_button`, `native_key`, `native_orientation`, or `native_screenshot` when a step already has normalized coordinates, needs high-throughput simulator input, or needs Simulator-only operations.
