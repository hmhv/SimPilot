# Build & Install

## Overview

A prerequisite step that builds the app from source and installs it on the iOS Simulator.

- If `config.json` has a `build` section, build once at the start of a test execution session
- If there is no `build` key, the app is assumed to be already installed and the build step is skipped
- Build artifacts go to Xcode's default DerivedData, shared with builds made from Xcode itself
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
find . -name "*.xcworkspace" -not -path "*.xcodeproj/*" -maxdepth 2
find . -name "*.xcodeproj" -maxdepth 2
```

Scheme detection uses `xcodebuild -list`:

```bash
xcodebuild -list -project MyApp.xcodeproj 2>/dev/null | grep -A 50 "Schemes:" | grep "^    "
```

- If only one scheme is found it is selected automatically; if multiple, ask the user
- Detection results are saved to `config.json` to avoid re-detection on subsequent runs

## Build

Specify `-destination 'generic/platform=iOS Simulator'` for the build. A generic destination has no active architecture, so `ONLY_ACTIVE_ARCH` is forced to NO and both arm64 and x86_64 are built. Pass `'ARCHS=$(NATIVE_ARCH)'` to build a single slice — clean build time and DerivedData size both drop by nearly half.

Single quotes are required. `"ARCHS=$(NATIVE_ARCH)"` is command-substituted by the shell into an empty value, and the build fails with `error: Build input file cannot be found`.

Builds may fail due to macro or SPM plugin validation, so always include the following flags:

- `-skipMacroValidation` — skip Swift Macro validation
- `-skipPackagePluginValidation` — skip SPM plugin validation

`-derivedDataPath` is intentionally not passed: the default DerivedData is shared with Xcode's own builds, so work done here is reused when the project is opened in Xcode.

`-quiet` prints nothing on success and keeps every diagnostic on failure — file, line, source excerpt, linker symbols, warnings. Judge the result by the exit code. If those diagnostics are not enough to fix the build, re-run the same command without `-quiet` for the full log.

### clean or not

| Caller | Action | Why |
|---|---|---|
| test / suite run | `clean build` | A regression verdict has to come from a reproducible artifact |
| verify | `build` | A one-off check right after a change; `clean` only adds wait time |

Also use `clean build` after changing build settings, or when a stale-cache
problem is suspected.

### Build Flow

```bash
# 1. Build (test/suite run: `clean build`, verify: `build`)
xcodebuild -project MyApp.xcodeproj -scheme MyApp \
  -destination 'generic/platform=iOS Simulator' \
  'ARCHS=$(NATIVE_ARCH)' \
  -skipMacroValidation -skipPackagePluginValidation \
  -quiet clean build

# 2. Get the .app path and bundle id (pass the same -destination as the build)
SETTINGS=$(xcodebuild -project MyApp.xcodeproj -scheme MyApp \
  -destination 'generic/platform=iOS Simulator' \
  -showBuildSettings -json 2>/dev/null)

# One entry per build target in the scheme, ordered by target name — NOT app
# first. Take the entry whose PRODUCT_TYPE is an application, and stop if there
# is none: continuing with an unset index resolves APP_PATH to "/".
IDX=""
N=0
while TYPE=$(printf '%s' "$SETTINGS" | plutil -extract "$N.buildSettings.PRODUCT_TYPE" raw - 2>/dev/null); do
  if [ "$TYPE" = "com.apple.product-type.application" ]; then IDX="$N"; break; fi
  N=$((N + 1))
done
[ -n "$IDX" ] || { echo "no application target in scheme MyApp" >&2; exit 1; }

APP_PATH="$(printf '%s' "$SETTINGS" | plutil -extract "$IDX.buildSettings.BUILT_PRODUCTS_DIR" raw -)/$(printf '%s' "$SETTINGS" | plutil -extract "$IDX.buildSettings.FULL_PRODUCT_NAME" raw -)"
BUNDLE_ID=$(printf '%s' "$SETTINGS" | plutil -extract "$IDX.buildSettings.PRODUCT_BUNDLE_IDENTIFIER" raw -)
```

- Passing the same `-destination` matters: omit it and the returned path is `Debug-iphoneos`
- Do not hardcode entry `0`. A scheme that also builds a framework returns an
  entry for it, and the entries come back in target-name order: a project with
  `AAAKit.framework` and `MyApp.app` puts the framework at `0`, so `APP_PATH`
  would be a `.framework` and `simctl install` would fail. Embedded app
  extensions do not add entries
- The loop takes the FIRST application entry. If a scheme builds more than one
  app (an app plus a helper app), name the target you want instead:
  `plutil -extract "$N.target" raw -` says which entry is which
- Takes under a second, so run it after every build rather than caching the path
- For `-workspace`, replace `-project` with `-workspace MyApp.xcworkspace`
- For SPM, omit `-project`/`-workspace` and specify only `-scheme`
- If `configuration` is specified, add `-configuration Release` (defaults to Debug if omitted)

### Build Artifact Layout

```
~/Library/Developer/Xcode/DerivedData/MyApp-<hash>/
  Build/Products/Debug-iphonesimulator/
    MyApp.app        ← build artifact
```

The `<hash>` is not predictable. Always resolve the path with `-showBuildSettings -json` as above; never guess it or hunt for it with `find`.

## Install

```bash
# Install (overwrites existing version)
xcrun simctl install $UDID "$APP_PATH"

# Verify installation
xcrun simctl listapps $UDID 2>/dev/null | grep -q "$BUNDLE_ID" && echo "OK"
```

### Clean Install

When the user explicitly requests a clean install, or when test instructions require fresh app state:

```bash
xcrun simctl uninstall $UDID $BUNDLE_ID 2>/dev/null
xcrun simctl install $UDID "$APP_PATH"
```

## Automatic Bundle ID Retrieval

After a build, take `PRODUCT_BUNDLE_IDENTIFIER` from `-showBuildSettings -json` (see Build Flow). For a `.app` with no project at hand:

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
