# Build & Install

## Overview

A prerequisite step that builds the app from source and installs it on the iOS Simulator.

- If `config.json` has a `build` section, build once at the start of a test execution session
- If there is no `build` key, the app is assumed to be already installed and the build step is skipped
- Build artifacts are stored in `.simpilot/build/` (recreated with a clean build each time)
- For suites and multi-device runs, the built `.app` is shared across all tests and all devices

## The build section in config.json

```json
{
  "build": {
    "project": "MyApp.xcodeproj",
    "scheme": "MyApp"
  }
}
```

- `project`: `.xcworkspace` is also accepted (auto-detected if omitted)
- `scheme`: detected via `xcodebuild -list` if omitted
- `configuration`: defaults to Debug if omitted
- All fields are optional. Writing just `"build": {}` enables fully automatic detection mode
- If the `build` key itself is absent, the build step is skipped

## Automatic Project Detection

When `project`/`scheme` are not specified, detection proceeds in this order:

1. Search for `.xcworkspace` at the repository root (excluding those inside `.xcodeproj`)
2. If not found, search for `.xcodeproj`
3. If not found, search for `Package.swift` (SPM project)
4. If multiple are found, ask the user

```bash
find . -name "*.xcworkspace" -not -path "*/.xcodeproj/*" -maxdepth 2
find . -name "*.xcodeproj" -maxdepth 2
```

Scheme detection uses `xcodebuild -list`:

```bash
xcodebuild -list -project MyApp.xcodeproj 2>/dev/null | grep -A 50 "Schemes:" | grep "^    "
```

- If only one scheme is found it is selected automatically; if multiple, ask the user
- Detection results are saved to `config.json` to avoid re-detection on subsequent runs

## Build

Specify `-destination 'generic/platform=iOS Simulator'` for the build.

Builds may fail due to macro or SPM plugin validation, so always include the following flags:

- `-skipMacroValidation` — skip Swift Macro validation
- `-skipPackagePluginValidation` — skip SPM plugin validation

### Build Flow

```bash
# 1. Clean build
xcodebuild -project MyApp.xcodeproj -scheme MyApp \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .simpilot/build/DerivedData \
  -skipMacroValidation -skipPackagePluginValidation \
  clean build 2>&1 | tee /tmp/simpilot-build.log | tail -5

# Check build result
# zsh uses $pipestatus (lowercase, 1-indexed); bash uses $PIPESTATUS (uppercase, 0-indexed)
if [ ${pipestatus[1]:-${PIPESTATUS[0]:-0}} -ne 0 ]; then
  echo "=== Build Error ==="
  grep -E "error:|Build FAILED|fatal error" /tmp/simpilot-build.log | head -20
  echo "=== Full log: /tmp/simpilot-build.log ==="
fi

# 2. Get the .app path
APP_PATH=$(find .simpilot/build/DerivedData/Build/Products -name "*.app" -type d | head -1)
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP_PATH/Info.plist")
```

- For `-workspace`, replace `-project` with `-workspace MyApp.xcworkspace`
- For SPM, omit `-project`/`-workspace` and specify only `-scheme`
- If `configuration` is specified, add `-configuration Release` (defaults to Debug if omitted)

### Build Artifact Layout

```
.simpilot/build/
  DerivedData/       ← xcodebuild DerivedData
    Build/Products/Debug-iphonesimulator/
      MyApp.app      ← build artifact
```

## Install

```bash
# Uninstall existing version (no error if not installed)
xcrun simctl uninstall $UDID $BUNDLE_ID 2>/dev/null

# Install the built .app
xcrun simctl install $UDID "$APP_PATH"

# Verify installation
xcrun simctl listapps $UDID 2>/dev/null | grep -q "$BUNDLE_ID" && echo "OK"
```

## Automatic Bundle ID Retrieval

```bash
/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" <path-to-.app>/Info.plist
```

If the `app` field in `config.json` is not set, it is automatically retrieved and set after the build.

## Direct Install from .app / .ipa

For installing a `.app` bundle directly from CI artifacts or shared by another team (no source code):

```bash
# Install .app
xcrun simctl install $UDID /path/to/MyApp.app

# Automatically retrieve Bundle ID (if not set in config.json)
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" /path/to/MyApp.app/Info.plist)
```

For `.ipa` files, extract first:
```bash
unzip MyApp.ipa -d /tmp/app_extract
APP_PATH=$(find /tmp/app_extract -name "*.app" -type d | head -1)
xcrun simctl install $UDID "$APP_PATH"
```

For build error details, see troubleshooting.md.
