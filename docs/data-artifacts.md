# Test data and evidence artifacts

SimPilot does not mirror commands already available in `xcrun simctl`. The
commands in this document cover the filesystem composition, validation, and
run-artifact behavior that simctl does not provide itself.

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
root and reports how many remain; for a mixed harness manifest, repeat the
command for its data container and each `--group`, then use `files-app cleanup`
for Files.app entries.

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

## Harness fixtures and persistent-state assertions

Fixture sources are relative to the `.simpilot` workspace. They are installed
before launch and restored after the test. The manifest and backups allow
recovery after an interrupted run. Recovery metadata is written before each
container mutation, and the app is terminated before both installation and
restoration. `--no-launch` therefore cannot be combined with fixtures. After a
successful restoration, the harness empties the manifest and removes its
recovery backups so a completed run cannot be replayed accidentally.

```json
{
  "id": "import-account",
  "title": "Import account fixture",
  "fixtures": [
    {
      "source": "fixtures/account.json",
      "destination": "Documents/Inbox/account.json"
    }
  ],
  "steps": [
    {
      "verify": {
        "container-files": [
          {
            "path": "Library/Application Support/state.json",
            "format": "json",
            "key-path": "$.loggedIn",
            "equals": true
          }
        ]
      }
    }
  ]
}
```

A fixture may set `group-id`, or set `files-app: true` with an optional
`storage` candidate path. Those modes are mutually exclusive. Files.app
fixtures must be verified through the app UI; `container-files` cannot target
File Provider Storage.

Container assertions support `exists`, `size`, `sha256`, and `equals`.
Inspection formats are `metadata`, `text`, `json`, `plist`, and `sqlite`.
JSON/plist assertions may use `key-path`; SQLite assertions use a read-only
`query`. SQLite runs in the CLI's safe mode, which disables filesystem helper
functions such as `readfile()` and `writefile()`.

An `equals` comparison trims leading and trailing whitespace on both sides, so
an app-written file that ends in a newline still matches an expectation without
one. With `format: "text"` — including the default when `equals` is present and
`format` is not — `equals` must be a string, and the file must be valid UTF-8;
assert `sha256` or `format: "metadata"` for binary files. `container inspect`
itself reports the file's text unmodified; only assertions trim.

Container verification resolves each app/App Group root once per step. A
transient JSON, plist, or SQLite read error is treated as an unmet poll result,
not as an action failure, so it does not repeat the UI action. Hashes are read
only when a `sha256` assertion requests them.

## Automatic evidence

Runs capture filtered unified logs to `logs.ndjson` by default. The default
predicate includes the bundle-ID subsystem and installed process name for the
run bundle plus every test-level `app` override. An empty capture is reported as
an evidence warning. An explicit predicate replaces that automatic predicate;
configure it in `.simpilot/config.json` when the apps use other logging
identities:

```json
{
  "app": "com.example.app",
  "capture-logs": true,
  "log-predicate": "subsystem == 'com.example.app'",
  "capture-container-diff": true
}
```

Log-stream stderr is kept separate from `logs.ndjson`; non-empty stderr is
linked as its own artifact and reported as an evidence warning. The `log stream`
filter banner and completion footer are removed from stdout, and every remaining
line in `logs.ndjson` is a JSON record. Empty-capture warnings use the resulting
record count rather than raw file size.

When enabled and capture succeeds, each test records its primary app data
container as `container-before.json`, `container-after.json`, and
`container-diff.json`. App Groups and Files.app storage are not included. The
before snapshot is taken after fixtures are applied, so the diff describes
changes the test made in the primary data container rather than fixture
installation. Use `container-files` with `group-id` for in-step App Group
assertions, and UI verification for Files.app. Whole-snapshot and per-file
failures become evidence warnings instead of silently removing evidence. App-specific
`.ips`/`.crash` files created during the run are collected for the run bundle
and every test-level `app` override, copied to `crash-reports/`, and indexed by
`crash-reports.json`. Artifact links and evidence warnings appear in
`report.html`.

Snapshot artifacts contain relative paths, sizes, modification timestamps, and
SHA-256 values. Files that disappear or cannot be read during a live snapshot
are listed in the snapshot's `errors` field and surfaced as evidence warnings;
one transient file does not discard the rest of the snapshot. Snapshots do not
copy file contents. `container diff` rejects snapshots whose recorded roots do
not match.

Crash collection checks Simulator report directories and the host Diagnostic
Reports directory because Simulator app crashes may be written there. Host
reports are accepted only when their structured identifier exactly matches the
bundle ID, and recorded source names do not expose the host path. Crash reports
and fixture backups may contain app data and must be handled as sensitive test
artifacts.
