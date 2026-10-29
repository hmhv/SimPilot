# App data and evidence commands

SimPilot does not mirror commands already available in `xcrun simctl`. The
commands in this document cover the filesystem composition, inspection, and
evidence collection that simctl does not provide itself.

## Container operations

`sipi container` resolves the app data container or a named App Group through
`simctl get_app_container`, then constrains every user-authored path beneath that
root. Absolute paths, `..`, NUL bytes, and existing symlinks are rejected. The
device must be booted. `container list` includes dot files, because a container's
own metadata plists are worth inspecting.

```sh
sipi container path <udid> <bundle-id>
sipi container list <udid> <bundle-id> [--path Documents]
sipi container put <udid> <bundle-id> fixture.json \
  --destination Documents/Inbox/fixture.json \
  --manifest fixture-manifest.json
sipi container pull <udid> <bundle-id> Library/Preferences/example.plist out.plist
sipi container inspect <udid> <bundle-id> state.json \
  --format json --key-path '$.user.loggedIn'
sipi container inspect <udid> <bundle-id> store.sqlite \
  --format sqlite --query 'select * from items'
sipi container snapshot <udid> <bundle-id> --output before.json
sipi container diff before.json after.json --output diff.json
sipi container cleanup <udid> <bundle-id> fixture-manifest.json
```

Pass `--group <group-id>` to target an App Group, including on `cleanup`. `put`
backs up an existing destination and persists the recovery entry before
replacement. Cleanup verifies the selected container and backup before touching
the fixture destination. Keep the manifest and its sibling backup directory
together until cleanup succeeds. Cleanup removes only entries for the selected
root and reports how many remain; for a manifest that spans several roots,
repeat the command for its data container and each `--group`, then use
`files-app cleanup` for Files.app entries.

## Files.app storage

Direct File Provider Storage access is experimental. It is a workaround for
Simulator versions where the documented share-to-Simulator flow does not place
arbitrary files in Files.app.

```sh
sipi files-app candidates <udid>
sipi files-app put <udid> fixture.json \
  --destination Imports/fixture.json \
  --storage '<one candidate path>' \
  --manifest files-app-manifest.json
sipi files-app cleanup <udid> files-app-manifest.json \
  --storage '<the same candidate path>'
```

The command discovers `File Provider Storage` beneath the selected Simulator's
random App Group UUID. It refuses an ambiguous result unless `--storage` names
one of the discovered candidates. It never guesses a UUID.
Discovery currently uses CoreSimulator's default device set.

## xcappdata

SimPilot creates and validates the package. Installation remains a direct
simctl operation.

```sh
sipi xcappdata create <udid> <bundle-id> fixture.xcappdata
sipi xcappdata validate fixture.xcappdata --bundle-id <bundle-id>
xcrun simctl install_app_data <udid> fixture.xcappdata
```

`install_app_data` compatibility has varied across Xcode/runtime releases, so a
package should be validated and tested on every supported toolchain.

## Snapshots

Snapshot artifacts contain relative paths, sizes, modification timestamps, and
SHA-256 values. Files that disappear or cannot be read during a live snapshot
are listed in the snapshot's `errors` field; one transient file does not discard
the rest of the snapshot. Snapshots do not copy file contents. `container diff`
rejects snapshots whose recorded roots do not match.

`container inspect` supports the `metadata`, `text`, `json`, `plist`, and
`sqlite` formats. JSON and plist reads may use `--key-path`; SQLite reads use a
read-only `--query` and run in the CLI's safe mode, which disables filesystem
helper functions such as `readfile()` and `writefile()`.

## Crash reports

```sh
sipi crash-evidence <udid> <bundle-id> <output-dir> --since <ISO 8601 timestamp with offset>
```

Collection checks Simulator report directories and the host Diagnostic Reports
directory because Simulator app crashes may be written there. Host reports are
accepted only when their structured identifier exactly matches the bundle ID,
and recorded source names do not expose the host path. Crash reports and fixture
backups may contain app data and must be handled as sensitive.
