# Cleaning Up Developer Data

Xcode and the simulators leave data behind that grows without bound. This covers
only that data — anything else on the Mac is out of scope.

## The rule

1. List everything in the table below that is there, with sizes — including
   what the user will likely keep.
2. Show the user the whole list, what each item is, and what removing it costs.
3. Remove only what the user selected, item by item.

Files go to the Trash with `/usr/bin/trash`, never `rm`, so a mistake can be
undone. The space comes back only once the user empties the Trash — say so in
the report. Devices and runtimes are removed with `simctl`, which deletes them
outright — say so when asking.

## What to look at

| What | Where | Removing it |
|---|---|---|
| DerivedData | `~/Library/Developer/Xcode/DerivedData/*` | Rebuilt by the next build. Not while Xcode or a build is running — see below |
| Archives | `~/Library/Developer/Xcode/Archives/*` | **Cannot be rebuilt.** They hold submitted builds and the dSYMs that symbolicate their crash reports. Only per archive, on explicit approval |
| Device support | `~/Library/Developer/Xcode/*DeviceSupport/*` | Copied again the next time that physical device connects |
| SwiftPM cache | `~/Library/Caches/org.swift.swiftpm` | Downloaded again on the next resolve |
| CoreSimulator caches | `~/Library/Developer/CoreSimulator/Caches` | Rebuilt on demand |
| Unavailable devices | `xcrun simctl list devices unavailable` | `xcrun simctl delete unavailable` |
| SwiftUI preview devices (`~/Library/Developer/Xcode/UserData/Previews`) | `xcrun simctl --set previews list devices` | `xcrun simctl --set previews delete all` — Xcode recreates them |
| Simulator devices | `~/Library/Developer/CoreSimulator/Devices/<udid>` — see below for sizes | `xcrun simctl erase <udid>` keeps the device and wipes its apps and data (shut it down first); `xcrun simctl delete <udid>` removes it |
| Parallel-testing clones (`~/Library/Developer/XCTestDevices`) | `xcrun simctl --set testing list devices` | `xcrun simctl --set testing delete all` — recreated per test run |
| Runtimes | `xcrun simctl runtime list` | `xcrun simctl runtime delete <identifier>`, or `--unusable` / `--outdated` (a newer build of the same runtime is installed) / `--notUsedSinceDays <n>`; always `--dry-run` first |
| Old Xcodes | `/Applications/Xcode*.app` | See `xcode.md` § Remove an Xcode |
| Interrupted Xcode installs | `/Applications/.sipi-xcode-*` | Left when `sipi xcode install` is killed mid-way. Only while no install is running (`pgrep -f '[s]ipi xcode install'` prints nothing) |
| Xcode's coding assistant agents | `~/Library/Developer/Xcode/CodingAssistant/Agents/*` | The agent binaries Xcode downloaded; `Agents/XcodeVersions/<build>` names the Xcode builds they served, so those for Xcodes no longer installed are leftovers. Whether Xcode downloads them again is unmeasured |
| Coding assistant history | The rest of `~/Library/Developer/Xcode/CodingAssistant` | **Cannot be rebuilt:** the assistant's settings, conversations, memories, skills and sign-in |
| Organizer product data | `~/Library/Developer/Xcode/Products` | App icons and data the Organizer shows per app. Whether it is fetched again is unmeasured |
| Physical device logs | `~/Library/Developer/Xcode/DeviceLogs` | **Cannot be rebuilt:** crash and other logs copied from physical devices |
| Playground devices | `~/Library/Developer/XCPGDevices` | Simulator devices Xcode made for playgrounds |
| Other tools' data | Any other folder in `~/Library/Developer` | Name the tool it belongs to (e.g. `XcodeBuildMCP` holds that tool's DerivedData and logs) and what it holds |

Before removing DerivedData, check that nothing is building — this prints
nothing and exits 1 when it is safe:

```bash
pgrep -x 'Xcode|xcodebuild|XCBBuildService'
```

## Listing sizes

```bash
setopt null_glob 2>/dev/null   # zsh: a pattern with no match must not abort the line
du -sh ~/Library/Developer/Xcode/DerivedData/* \
  ~/Library/Developer/Xcode/Archives/*/* \
  ~/Library/Developer/Xcode/*DeviceSupport/* \
  ~/Library/Caches/org.swift.swiftpm \
  ~/Library/Developer/CoreSimulator/Caches \
  ~/Library/Developer/Xcode/UserData/Previews \
  ~/Library/Developer/XCTestDevices \
  ~/Library/Developer/XCPGDevices \
  ~/Library/Developer/Xcode/CodingAssistant/Agents/* \
  ~/Library/Developer/Xcode/CodingAssistant \
  ~/Library/Developer/Xcode/Products \
  ~/Library/Developer/Xcode/DeviceLogs \
  /Applications/Xcode*.app \
  /Applications/.sipi-xcode-* 2>/dev/null | sort -h
xcrun simctl runtime list -v | grep -E '^[a-zA-Z]+ [0-9]|Size:|Last Used'   # each runtime's size on disk and last use
ls ~/Library/Developer/Xcode/CodingAssistant/Agents/XcodeVersions   # Xcode builds the agents served
ls ~/Library/Developer    # anything not in the table is another tool's
```

A DerivedData folder's `info.plist` names the project it belongs to
(`WorkspacePath`), which tells the user what they would be throwing away:

```bash
plutil -extract WorkspacePath raw ~/Library/Developer/Xcode/DerivedData/<folder>/info.plist
```

A folder without an `info.plist` is either a cache shared by every project
(`*.noindex`, `SDKExplicitPrecompiledModules`), rebuilt on demand, or a project
folder whose metadata is gone — name it to the user by its folder name.

Each simulator device's data, largest last, with its name:

```bash
for d in ~/Library/Developer/CoreSimulator/Devices/*/; do
  u=$(basename "$d")
  printf '%s\t%s\t%s\n' "$(du -sh "$d" 2>/dev/null | cut -f1)" "$u" \
    "$(xcrun simctl list devices | grep "$u" | sed -E 's/ \([0-9A-F-]{36}\).*//; s/^ *//')"
done | sort -h
```

## Removing

```bash
/usr/bin/trash ~/Library/Developer/Xcode/DerivedData/MyApp-abc123
xcrun simctl delete unavailable
xcrun simctl runtime delete --unusable --dry-run    # then again without --dry-run
```
