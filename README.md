# SimPilot

Translations: **English** | [日本語](README.ja.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [Español](README.es.md) | [한국어](README.ko.md) | [Português do Brasil](README.pt-BR.md)

SimPilot lets Claude Code or Codex drive the iOS Simulator from natural language — read the screen, tap, type, fold, capture, put files in the app and read back what it saved — and keeps the Xcode and simulator toolchain behind it installed and clean. How to check a result is left to the agent: it reads the screen, captures it, and reads the app's data in whatever way fits the task.

The top-level README is translated. Skill docs and code remain in English.

## What it does

- **Drive the simulator** — `sipi` reads the accessibility tree and acts on it natively and headlessly: taps by label or id, text entry in any script, gestures, hardware buttons, rotation, folding an iPhone Duo, screenshots and video, Face ID / Touch ID, the accessibility appearance settings, and memory-pressure warnings.
- **Work with app data** — put files into the app's data container, an App Group, or Files.app; inspect what the app saved as text, JSON, plist, or SQLite; snapshot and diff the container; collect the app's crash reports.
- **Manage Xcode and simulator runtimes** — `sipi xcode list / install / uninstall` show, install and remove Xcode releases, and `sipi runtime list` shows the simulator runtimes Apple offers; installing and removing runtimes and devices go through `xcodebuild` and `simctl`, as the skill describes.
- **Clean up** — find and remove what Xcode and the simulators leave behind: DerivedData, device support files, preview and test devices, unusable runtimes, old Xcodes. Nothing is removed without approval, and files go to the Trash.

## Prerequisites

- Xcode 27.2 or later
- macOS 26.6 or later
- [Claude Code](https://claude.com/claude-code) or Codex

## Installation

SimPilot ships as a single `sipi` binary with the skill embedded. Install it with one command:

```bash
curl -fsSL https://raw.githubusercontent.com/hmhv/SimPilot/main/install.sh | bash
```

The installer downloads the prebuilt `sipi` binary, then `sipi` installs the embedded `sipi-common` skill into:

- Claude Code (`~/.claude/skills/`)
- Codex (`~/.agents/skills/`)

Verify the simulator capabilities with `sipi doctor`.

To update and uninstall:

```bash
sipi update      # download the latest sipi from GitHub Releases and refresh the skill
sipi uninstall   # remove the skill, install metadata, and the sipi binary
```

Updating from 2.x removes the `sipi-test` and `sipi-verify` skills. In your app repositories, `.simpilot/tests/`, `suites/`, `devices/`, `runs/` and `verify/`, and every `config.json` key other than `app` and `build`, are no longer used — delete them when you no longer need them.

## Quick start

In your iOS app project:

- Claude Code: `/sipi-common` followed by the request, or just ask
- Codex: mention the skill, for example `Use the sipi-common skill to ...`

```text
/sipi-common Build the app and check that the new login flow works on the simulator
/sipi-common Open settings and turn on notifications
/sipi-common Put sample.pdf in the app's Inbox and check the import screen
/sipi-common Show what the app saved after signing in
/sipi-common Install Xcode 27.2 and the iOS 27.2 runtime
/sipi-common Clean up Xcode's disk usage
```

On first use, SimPilot detects your project, creates `.simpilot/config.json`, and prepares the simulator.

## Driving the simulator directly

`sipi` is a plain CLI an agent calls one step at a time. `describe-ui --format compact` prints the accessibility tree as one line per element — type, label, id, value, frame, tap point — at a fraction of the JSON size; `wait-for` polls until a label, id, value, or text appears (or disappears) instead of sleeping; `screenshot --max-pixel 600` returns a capture small enough to look at cheaply; `memory-warning` sends the memory-pressure warning that Simulator.app's Debug menu used to (Xcode 27+); `fold-state` reports which of an iPhone Duo's two screens is lit, `fold --closed|--open|--angle` folds it — something neither simctl nor devicectl can do — and `--display inner|cover` captures the screen that is dark. Run `sipi --help` for the full command set.

`sipi a11y-audit` checks the current screen against any booted simulator — undersized touch targets, unlabeled controls, ambiguous duplicate labels, meaningless labels, truncated text. Xcode's own accessibility audit only runs from inside a UI test target.

The app data commands are described in [App data and evidence commands](docs/data-artifacts.md).

## Xcode and simulator runtimes

```bash
sipi xcode install 27B48
```

Pass a build number from `sipi xcode list` (taken from [xcodereleases.com](https://xcodereleases.com)). A window opens on developer.apple.com; sign in there and it closes by itself. The session lives only in memory for that run — nothing is stored. The app is installed as `/Applications/Xcode-<version>.app` (for example `Xcode-27.2.0-release.candidate.app`). Selecting it needs root, so `sipi` prints the `sudo xcode-select -s …` and `sudo xcodebuild -runFirstLaunch` commands to run yourself.

`sipi runtime list` shows the simulator runtimes Apple offers, with the installed ones marked — neither `xcodebuild` nor `simctl` can list them. `xcodebuild -downloadPlatform iOS -buildVersion <version> -architectureVariant arm64` installs one, `xcrun simctl runtime delete` removes one, and `xcrun simctl create` makes devices. The skill knows these and runs them for you.

## Project files

SimPilot keeps two files in your project:

```text
.simpilot/
  config.json   # bundle ID and how to build the app
  notes.md      # app-specific interaction quirks the skill records
```

Both are worth committing: a teammate or another agent benefits from them.

## Known limitations

- Text entry defaults to writing the field's accessibility value (`set-text`), which needs no keyboard and takes any script. Keystroke-level entry (`type`) pastes through the clipboard by default; direct per-key HID typing covers the US keyboard layout only, and types the wrong characters if the guest's active keyboard is a different layout
- **A long-lived simulator can stop accepting keyboard HID** (measured on Xcode 27.0 beta 6): paste, per-key typing, and select-all+delete are all ignored while touch still works. This follows device age rather than the iOS version, and neither `simctl erase` nor a reboot revives it. `type` detects the condition and fails rather than reporting success; `set-text` is unaffected. `type --xcode-mcp` types through Xcode 27's own service instead, which rescued the device measured — with a cost, see below
- A tap that resolves to an element the accessibility tree claims is present, but whose visible area is not actually touchable, still reports success. `describe-point` returns the element, so nothing in the stack can tell the difference; Xcode's own tooling behaves the same way
- Contrast ratios and clipped text are out of scope for `sipi a11y-audit`; both need pixel analysis of the rendered frame
- **iPhone Duo** (measured on Xcode 27.2): taps, swipes, typing and hardware buttons reach both screens. The inner screen answers no accessibility hit-test, so a selector tap there goes to the element's frame unchecked, and `set-text` / `describe-point` work on the cover only. While Device Hub is open it takes the device's input over — the inner screen drops taps, and the Mac's clipboard replaces the simulator's pasteboard, so `type` refuses to paste. `sipi doctor` reports it and `sipi repair-input` reconnects input. Nothing can rotate a Duo simulator from a script; use Device Hub's rotate button
- Simulator only — physical devices are not supported

## Typing on a simulator that stopped accepting keystrokes

A simulator can reach a state where it ignores the keyboard events SimPilot
injects. Touch keeps working; paste, per-key typing and select-all+delete do
not. SimPilot sends exactly the same events on a healthy and an affected
device, so there is nothing on its side to fix — but Xcode 27's own
device-interaction service types through a different path, which the affected
device measured still accepted (a device worn further ignored that one too), and
that path also ignores the guest's keyboard layout.

`sipi type --xcode-mcp` selects that path. SimPilot never takes it on its own: on iOS 27 one such session leaves
every app launched afterwards on that device with an empty accessibility tree
until the device restarts (`simctl shutdown` + `boot`), so use it last, or
restart before the next launch. Everything else in SimPilot works without any of
this, and `set-text` never needs a keyboard at all.

Three things must be true before it can be used:

```bash
xcode-select -p                    # Xcode 27.2 or later
sudo xcrun mcp-server enable       # turn headless mode on
sipi xcode-mcp --approve <path to an .xcodeproj or .xcworkspace>
```

The project is opened only to raise Xcode's approval prompt and is closed again
immediately. Once set up, sipi starts the service if it is not already running.
Xcode ties the grant to the exact binary, so `sipi update` or a rebuild means
running the approve step once more. `sipi xcode-mcp` reports the current state —
including a grant that belongs to an earlier build at the same path — and
`sipi doctor` says whether the path is available.

`--clear` cannot use this path: select-all and delete are keystrokes too, and
the service types but cannot empty a field. Use `sipi set-text` to replace a
value outright.

The cost belongs to the session, not the typing: re-measured on Xcode 27.2, a session of one tap left every app launched afterwards with an empty accessibility tree until the device restarted.

## Note

This repository is primarily managed by AI. Issues and feedback are welcome, but pull requests are not accepted. If you want to adapt it for your own workflow, please fork it and use your own copy.

## Disclaimer

SimPilot is a development tool. It drives the iOS Simulator through Apple's **undocumented private frameworks**, which Apple may change or remove in any Xcode or macOS update — that can break SimPilot without notice. It is not affiliated with or endorsed by Apple, and is not intended for App Store or production use. It is provided **as-is, without warranty — use at your own risk.**

## License

MIT © 2026 hmhv. See [LICENSE](LICENSE).
