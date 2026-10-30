# Xcode and Simulator Runtimes

Everything here except installing Xcode itself is plain `xcode-select`,
`xcodebuild`, and `xcrun simctl` — call them directly.

## Installed Xcodes

```bash
xcode-select -p    # the selected developer directory
setopt null_glob 2>/dev/null   # zsh: no Xcode installed must not abort the loop
for app in /Applications/Xcode*.app; do
  [ -d "$app" ] || continue    # bash leaves an unmatched pattern as is
  printf '%s  %s (%s)\n' "$app" \
    "$(defaults read "$app/Contents/Info" CFBundleShortVersionString)" \
    "$(defaults read "$app/Contents/version" ProductBuildVersion)"
done
```

## Xcodes Apple offers

The list comes from xcodereleases.com and needs no sign-in or developer tools:

```bash
"$SIPI" xcode list [--beta]    # this macOS generation and the one before: version, build, date, minimum macOS
```

## Install Xcode

```bash
"$SIPI" xcode install <build>    # e.g. 27B48
```

- Pass the build number from the list above. sipi refuses a release that needs
  a newer macOS than this Mac runs. When several entries share it,
  sipi takes the release over the RC over a beta, and the Apple silicon archive
  over the Universal one.
- A window opens on developer.apple.com. **The user signs in there** — tell them
  before running, and wait; the window closes by itself once the session works.
  Nothing from the session is stored, so every install asks again.
- The download is several GB and expanding it takes minutes. Run it in the
  background and tell the user it takes a while.
- The app lands at `/Applications/Xcode-<version>.app`
  (e.g. `Xcode-27.2.0-release.candidate.app`); sipi refuses to overwrite one that
  exists.

## Select an Xcode

`xcode-select -s` needs root and changes the developer directory for every user
on the Mac. Do not run it yourself: give the user the commands `sipi xcode
install` printed, to run in their own terminal (in Claude Code, as `! sudo …`):

```bash
sudo xcode-select -s /Applications/Xcode-27.2.0-release.candidate.app
sudo xcodebuild -runFirstLaunch
```

To use another Xcode for a single command, set `DEVELOPER_DIR` instead:

```bash
DEVELOPER_DIR=/Applications/Xcode-27.2.0-release.candidate.app/Contents/Developer xcodebuild -version
```

## Remove an Xcode

Confirm the exact app with the user, then:

```bash
"$SIPI" xcode uninstall <build>    # e.g. 27A9275; moves it to the Trash
```

It refuses the selected Xcode (`xcode-select -p` or `DEVELOPER_DIR`) and a
running one. When two apps hold the same
build, pass the app's path instead of the build number.

## Xcode's own agent skills

Xcode 27.2 carries agent skills of its own (device-interaction, app-resizability,
swiftui-specialist, xctrace, …). Ask the user where they should go, then:

```bash
xcrun agent skills export <dir>                       # one folder per skill
xcrun agent skills export --replace-existing <dir>    # overwrite ones already there
```

It talks to the selected Xcode; a skill folder that already exists is skipped
unless `--replace-existing` is passed.

## Simulator runtimes

| Need | Command |
|---|---|
| What Apple offers (installed ones marked) | `"$SIPI" runtime list [--platform iOS] [--beta]` — no developer tools needed |
| What is installed, with identifiers | `xcrun simctl runtime list` (`-j` for JSON) |
| Download for the selected Xcode | `xcodebuild -downloadPlatform iOS -architectureVariant arm64` — also `watchOS`, `tvOS`, `visionOS` |
| Download a specific OS | `xcodebuild -downloadPlatform iOS -buildVersion 18.6 -architectureVariant arm64` — `-buildVersion` also takes a build from `sipi runtime list`, to pick one of two runtimes with the same version |
| Add a runtime `.dmg` | `xcodebuild -importPlatform <path.dmg>` |
| Delete | `xcrun simctl runtime delete <identifier>` — add `--dry-run` first |

Deleting a runtime shuts down its booted simulators first. Devices built on it
stay listed as unavailable; `clean.md` covers removing those.

## Devices

```bash
xcrun simctl list devicetypes                       # device type identifiers
xcrun simctl list runtimes                          # installed runtime identifiers
xcrun simctl create "iPhone 17" <devicetype-id> <runtime-id>
xcrun simctl rename <udid> "New name"
xcrun simctl clone <udid> "Copy name"               # same runtime, same data
xcrun simctl boot <udid>                            # no window needed
xcrun simctl shutdown <udid>
xcrun simctl erase <udid>                           # wipe content and settings; device must be shut down
xcrun simctl delete <udid>
```

### Pair an Apple Watch

Create the watch on the watchOS runtime released with the phone's iOS — the
numbers match from 26 on (iOS 27 ↔ watchOS 27); before that iOS 18 ↔ watchOS 11,
iOS 17 ↔ watchOS 10 — then pair and activate:

```bash
xcrun simctl create "Apple Watch" <watch-devicetype-id> <watchos-runtime-id>
xcrun simctl pair <watch-udid> <phone-udid>         # prints the pair id
xcrun simctl pair_activate <pair-id>
xcrun simctl unpair <pair-id>
```

### A device shows as unavailable

`xcrun simctl list -j devices` groups devices under the runtime identifier they
need (e.g. `com.apple.CoreSimulator.SimRuntime.iOS-18-6`) and gives an
`availabilityError`. Turn the identifier into a version (18.6), find it with
`"$SIPI" runtime list --platform iOS` (add `--beta` for a beta runtime), and
install it as in § Simulator runtimes. An identifier with a device suffix
(`iOS-27-2-iPhone19-4`) is a device's own runtime — see `foldables.md`.
