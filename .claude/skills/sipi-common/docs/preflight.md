# Preflight

Common preflight checks for all sipi-* skills. Complete every step before proceeding to the skill workflow.

## 1. Native Driver (`sipi doctor`)

Resolve the `sipi` binary path **once** at the start of the session and persist
the absolute path so later Bash calls do not re-run the resolver. Run the
resolver below; it prints a ready-to-paste `SIPI=…` line (shell-quoted via
`printf %q`, so paths with spaces are safe). Copy that whole line **verbatim**
as the first line of every subsequent UI Bash call (see `ui-driver.md`) — do not
re-quote it:

```bash
resolve_sipilot_root() {
  if [ -n "${SIPILOT_ROOT:-}" ] && [ -d "$SIPILOT_ROOT" ]; then
    printf '%s\n' "$SIPILOT_ROOT"
    return
  fi
  for root in \
    "$PWD" \
    "$(cd "$PWD/.." 2>/dev/null && pwd)" \
    "$(cd "$PWD/../.." 2>/dev/null && pwd)" \
    "$PWD/SimPilot"
  do
    # Accept a root only if its Package.swift is actually SimPilot's, so an
    # unrelated user Swift package on the parent path is never mistaken for it.
    if [ -f "$root/Package.swift" ] && \
       { [ -d "$root/Sources/sipi" ] || grep -q 'SimPilotKit' "$root/Package.swift"; }; then
      printf '%s\n' "$root"
      return
    fi
  done
  printf '%s\n' ""
}

# Prefer the installed sipi on PATH (install.sh puts it in ~/.local/bin); then
# the install location itself (sipi setup only PRINTS PATH advice, so a fresh
# curl|bash user may have it installed but not on PATH); then fall back to a
# contributor's release build inside the checkout.
SIPI="$(command -v sipi || true)"
if [ -z "$SIPI" ] && [ -x "$HOME/.local/bin/sipi" ]; then
  SIPI="$HOME/.local/bin/sipi"
fi
if [ -z "$SIPI" ]; then
  SIPILOT_ROOT="$(resolve_sipilot_root)"
  SIPI="$SIPILOT_ROOT/.build/release/sipi"
  if [ ! -x "$SIPI" ] && [ -f "$SIPILOT_ROOT/Package.swift" ]; then
    (cd "$SIPILOT_ROOT" && swift build -c release >/dev/null)
  fi
fi
if [ ! -x "$SIPI" ] && ! command -v sipi >/dev/null 2>&1; then
  echo "sipi not found — install it (curl -fsSL .../install.sh | bash) or build it: (cd <SimPilot> && swift build -c release)" >&2
  exit 1
fi
printf 'SIPI=%q\n' "$SIPI"   # prints a ready-to-paste line, e.g. SIPI=/Users/you/.local/bin/sipi — copy it verbatim into later UI calls
"$SIPI" doctor
```

`"$SIPI" doctor` checks that the native bridge can load CoreSimulator, SimulatorKit, and AccessibilityPlatformTranslation, resolve the required private symbols, and find a booted simulator. Exit code `0` means the native driver is ready; a non-zero exit means a capability is missing.

The resolver prefers `sipi` on `PATH`, then the install location (`~/.local/bin/sipi`, where `install.sh` puts it but `sipi setup` only prints PATH advice), then a release build inside the checkout (`.build/release/sipi`), building it on demand. If it cannot find `sipi` it hard-fails; if `"$SIPI" doctor` still fails, report the failing capability from its output and stop.

## 1.5 UI Driver

Read `ui-driver.md` before the first UI interaction. Use its shell prelude at the top of every Bash call that calls `ui_describe`, `ui_tap_label`, `ui_tap_id`, or `native_*`.

The UI driver uses the native `sipi` binary by default; it sees both the frontmost app tree and System UI. Use `ui_*` for inspection, taps, keys, and screenshots, and `native_*` for direct normalized-coordinate input or Simulator-only operations.

## 2. Booted Simulator

```bash
xcrun simctl list devices booted
```

If none found, attempt to boot one. If device selection is specified, resolve the model/runtime first.

Once the device is resolved, note the UDID and set it at the top of each Bash call:

```bash
UDID="<resolved-udid>"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print app" /dev/stdin <<< "$(plutil -convert xml1 -o - .simpilot/config.json)")
```

These variables do not persist between Bash calls — redefine them in each command.

After `UDID` is set, run a minimal readiness check with the full `ui-driver.md` prelude
(the `SIPI=` line preflight printed, plus the wrapper functions) so the call is
self-contained:

```bash
SIPI=/Users/you/.local/bin/sipi   # paste the SIPI= line printed above, verbatim (already shell-quoted)
UDID="<resolved-udid>"
[ -x "$SIPI" ] || { echo "sipi not found at '$SIPI'" >&2; exit 1; }
ui_describe()   { "$SIPI" describe-ui "$UDID" "$@"; }   # ...and the rest of the ui-driver.md prelude
ui_describe >/tmp/sipi-preflight.json
```


## 3. Config (`.simpilot/config.json`)

If `.simpilot/config.json` does not exist, bootstrap it: detect the Xcode project/workspace (or `Package.swift`) and scheme, write `config.json` with at minimum `{ "app": "<bundle-id>" }`, and add `.simpilot/` to `.gitignore`. The project/scheme detection algorithm is defined once in `build.md` (the single detection authority) — follow it there. Detection results are saved to `config.json` to avoid re-detection on subsequent runs.

## 4. Build & Install (optional)

If `config.json` has a `"build"` section, build and install the app once at the start of a session. If there is no `"build"` key, the app is assumed to be already installed.

See `build.md` for the full build and install procedure.
