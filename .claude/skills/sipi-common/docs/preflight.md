# Preflight

Complete every step before any simulator interaction.

## 1. Resolve the binary and run `sipi doctor`

Resolve the `sipi` path **once** per session and reuse the printed line; shell
state does not persist between Bash calls.

```bash
SIPI="$(command -v sipi || true)"
for candidate in "$HOME/.local/bin/sipi" "$PWD/.build/release/sipi" "$PWD/../.build/release/sipi"; do
  [ -n "$SIPI" ] && break
  [ -x "$candidate" ] && SIPI="$candidate"
done
[ -x "$SIPI" ] || { echo "sipi not found — install it (curl -fsSL https://raw.githubusercontent.com/hmhv/SimPilot/main/install.sh | bash) or build it (swift build -c release)" >&2; exit 1; }
printf 'SIPI=%q\n' "$SIPI"   # shell-quoted; paste this line into later calls
"$SIPI" doctor
```

**If the resolved path is not on `PATH`** — the `~/.local/bin` or
`.build/release` cases — then a bare `sipi` in any later call is
`command not found`. Start every subsequent Bash call with the printed `SIPI=`
line and invoke `"$SIPI"`. Examples in the other docs write bare `sipi` for
readability; substitute `"$SIPI"` whenever this applies.

`doctor` checks that the native bridge can load CoreSimulator, SimulatorKit, and
AccessibilityPlatformTranslation and resolve the required private symbols,
including the IndigoHID builders. It
also lists the booted simulators, but an empty list does not fail it — step 2
resolves the device.

**Exit 0 is the gate.** On a non-zero exit, re-run `"$SIPI" doctor --json` to read
the structured probe (`name` / `ok` / `detail` per check, plus a top-level
`allCorePresent`), name the exact missing capability, and stop.

`doctor` also prints informational `notes` that never affect the exit code: which
binary answered, when it was built, and — inside a SimPilot checkout — a warning
when HEAD is newer than the binary. **Act on that warning before driving
anything**: a stale install returns old behavior under the same version number,
so a fix that exists in source can look broken on the simulator. Rebuild,
reinstall, re-run `doctor`.

## 2. Resolve the device

```bash
"$SIPI" devices          # JSON, one "booted" boolean per device
```

`xcrun simctl list devices booted` is an equivalent fallback. If nothing is
booted, boot a device — booting needs no window. Use the model or runtime the
request names — an iPhone Duo for folding or two screens (`foldables.md`);
otherwise take an iPhone on the newest runtime from
`xcrun simctl list devices available`, and if there is none, create one
(`xcode.md` § Devices):

```bash
xcrun simctl boot <udid>
xcrun simctl bootstatus <udid> -b
```

Then confirm the driver can read the screen:

```bash
SIPI=/Users/you/.local/bin/sipi   # the line printed in step 1
UDID=<resolved-udid>
"$SIPI" describe-ui "$UDID" >/dev/null
```

Read `ui-driver.md` before the first interaction.

## 3. Config (`.simpilot/config.json`)

When the request involves an app and it does not exist, bootstrap it: detect the Xcode project/workspace (or
`Package.swift`) and scheme, and write `{ "app": "<bundle-id>", "build": { "project": …, "scheme": … } }`
— the bundle id comes from `-showBuildSettings` (`build.md`). Write only
`{ "app": "<bundle-id>" }` when there is no project and the app is already
installed.
Leave `config.json` and `notes.md` tracked: a teammate or another agent benefits
from them. `build.md` is the single authority for the detection algorithm —
follow it there. Save what you detect so later sessions skip detection.

A `.simpilot/` left by SimPilot 2.x may also hold `tests/`, `suites/`,
`devices/`, `runs/`, `verify/` and `config.json` keys other than `app` and
`build`. Nothing reads them any more; tell the user, and remove them only if they
agree.

## 4. Build & install (optional)

Build and install only when the request needs the current code: the user
changed it, asked to build or run it, or the app is not installed yet. Reading
the screen, capturing it, or driving the installed app needs neither — and an
install restarts the app, losing the screen it was on. See `build.md`.
