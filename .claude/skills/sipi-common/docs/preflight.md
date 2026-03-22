# Preflight

Common preflight checks for all sipi-* skills. Complete every step before proceeding to the skill workflow.

## 1. AXe CLI

```bash
which axe
```

If not found, tell the user to install with `brew install cameroncooke/axe/axe`, run `axe init`, and stop.

## 2. Booted Simulator

```bash
xcrun simctl list devices booted
```

If none found, attempt to boot one. If device selection is specified, resolve the model/runtime first.

Once the device is resolved, note the UDID and set it at the top of each Bash call:

```bash
UDID=<resolved-udid>
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print app" /dev/stdin <<< "$(plutil -convert xml1 -o - .simpilot/config.json)")
```

These variables do not persist between Bash calls — redefine them in each command.


## 3. Config (`.simpilot/config.json`)

If `.simpilot/config.json` does not exist, create it automatically:

1. Detect the Xcode project or workspace:
   - search for `.xcworkspace` at the repo root (excluding those inside `.xcodeproj`)
   - if not found, search for `.xcodeproj`
   - if not found, search for `Package.swift`
   - if multiple are found, ask the user
2. Detect the scheme via `xcodebuild -list`
   - if only one scheme, select automatically; if multiple, ask the user
3. Write `config.json` with at minimum `{ "app": "<bundle-id>" }`
4. Add `.simpilot/` to `.gitignore` if not already present

Detection results are saved to `config.json` to avoid re-detection on subsequent runs.

## 4. Build & Install (optional)

If `config.json` has a `"build"` section, build and install the app once at the start of a session. If there is no `"build"` key, the app is assumed to be already installed.

See `build.md` for the full build and install procedure.
