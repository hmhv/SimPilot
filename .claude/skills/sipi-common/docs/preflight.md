# Preflight

Complete every step before any simulator interaction. All three `sipi-*` skills
gate on this file.

## 1. Resolve the binary and run `sipi doctor`

Resolve the `sipi` path **once** per session and reuse the printed line; shell
state does not persist between Bash calls.

```bash
SIPI="$(command -v sipi || true)"
for candidate in "$HOME/.local/bin/sipi" "$PWD/.build/release/sipi" "$PWD/../.build/release/sipi"; do
  [ -n "$SIPI" ] && break
  [ -x "$candidate" ] && SIPI="$candidate"
done
[ -x "$SIPI" ] || { echo "sipi not found — install it (curl -fsSL .../install.sh | bash) or build it (swift build -c release)" >&2; exit 1; }
printf 'SIPI=%q\n' "$SIPI"   # shell-quoted; paste this line into later calls
"$SIPI" doctor
```

**If the resolved path is not on `PATH`** — the `~/.local/bin` or
`.build/release` cases — then a bare `sipi` in any later call is
`command not found`. Start every subsequent Bash call with the printed `SIPI=`
line and invoke `"$SIPI"`. Examples in the other docs write bare `sipi` for
readability; substitute `"$SIPI"` whenever this applies.

`doctor` checks that the native bridge can load CoreSimulator, SimulatorKit, and
AccessibilityPlatformTranslation, resolve the required private symbols, and find
a booted simulator.

**Exit 0 is the gate.** On a non-zero exit, re-run `"$SIPI" doctor --json` to read
the structured probe (`name` / `ok` / `detail` per check, plus a top-level
`allCorePresent`), name the exact missing capability, and stop.

`doctor` also prints informational `notes` that never affect the exit code: which
binary answered, when it was built, and — inside a SimPilot checkout — a warning
when HEAD is newer than the binary. **Act on that warning before verifying
anything**: a stale install returns old behavior under the same version number,
so a fix that exists in source can look broken on the simulator. Rebuild,
reinstall, re-run `doctor`.

## 2. Resolve the device

```bash
"$SIPI" devices          # JSON, one "booted" boolean per device
```

`xcrun simctl list devices booted` is an equivalent fallback. If nothing is
booted, boot a device — booting needs no window. When the request names a model
or runtime, resolve that first.

Then confirm the driver can read the screen:

```bash
SIPI=/Users/you/.local/bin/sipi   # the line printed in step 1
UDID=<resolved-udid>
"$SIPI" describe-ui "$UDID" >/dev/null
```

Read `ui-driver.md` before the first interaction.

## 3. Config (`.simpilot/config.json`)

If it does not exist, bootstrap it: detect the Xcode project/workspace (or
`Package.swift`) and scheme, write at minimum `{ "app": "<bundle-id>" }`, and add
`.simpilot/` to `.gitignore`. `build.md` is the single authority for the
detection algorithm — follow it there. Save what you detect so later runs skip
detection.

## 4. Build & install (optional)

If `config.json` has a `build` section, build and install once at the start of
the session. No `build` key means the app is assumed installed. See `build.md`.
