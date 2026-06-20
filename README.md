# SimPilot

Translations: **English** | [日本語](README.ja.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [Español](README.es.md) | [한국어](README.ko.md) | [Português do Brasil](README.pt-BR.md)

SimPilot is a set of agent skills for iOS app testing and verification on the iOS Simulator, driven by natural language requests in Claude Code or Codex.

The top-level README is translated. Skill docs and code remain in English.

## What it does

- **`/sipi-test`** — UI test automation on the iOS Simulator. Define tests in natural language; the skill automates interaction and verification. Supports regression suites, multi-device runs, and quality audits (accessibility, localization, appearance).
- **`/sipi-verify`** — Post-implementation verification on the iOS Simulator. Confirm that a feature or fix works correctly after code changes.

Results are saved in `.simpilot/` with HTML reports for browser viewing.

## Prerequisites

- macOS 15 or later
- Xcode 26 or later — needed at **runtime** to drive the Simulator (SimPilot loads Xcode's private Simulator frameworks). Not needed to install.
- [Claude Code](https://claude.com/claude-code) or Codex

## Installation

SimPilot ships as a single `sipi` binary with the skills embedded. Install it with one command:

```bash
curl -fsSL https://raw.githubusercontent.com/hmhv/SimPilot/main/install.sh | bash
```

The installer downloads the prebuilt `sipi` binary, then `sipi` installs the embedded `sipi-common` / `sipi-test` / `sipi-verify` skills into:

- Claude Code (`~/.claude/skills/`)
- Codex (`~/.agents/skills/`)

Verify the simulator capabilities with `sipi doctor`.

To update and uninstall:

```bash
sipi update      # download the latest sipi from GitHub Releases and refresh the skills
sipi uninstall   # remove the skills, install metadata, and the sipi binary
```

## Quick start

In your iOS app project:

- Claude Code: use slash commands such as `/sipi-test`
- Codex: mention the skill naturally, for example `Use the sipi-test skill to ...`

**Testing:**
```text
/sipi-test Create a test for switching between the home and settings tabs
Use the sipi-test skill to create a test for switching between the home and settings tabs
```
On first use, SimPilot detects your project, creates `.simpilot/config.json`, and prepares the simulator.

**Verification:**
```text
/sipi-verify Check that the new login flow works on the simulator
Use the sipi-verify skill to verify the dark mode fix looks correct
```

## Common tasks

**Create tests:**
```text
/sipi-test Create a test for the home screen tab switching
/sipi-test Create a test that logs in and opens settings
/sipi-test Create a test from the current screen
```

**Run tests:**
```text
/sipi-test Run the settings-navigation test
/sipi-test Run the regression suite
/sipi-test Run tests tagged smoke
/sipi-test Run the regression suite on iPhone 16 Pro
/sipi-test Run tests on iPhone 16 and iPhone 15
/sipi-test Run tests with the regression-profile device set
```

When multiple devices are specified, tests run in parallel. If `.simpilot/config.json` includes a `build` entry, the app is built before running.

**View results:**
```text
/sipi-test Show the latest results
/sipi-test Show failure details for the settings-toggle test
/sipi-test Show failure details for all failed tests
/sipi-test Open the HTML report
```

Each run generates `report.html` in the run directory. Results are saved under `.simpilot/runs/`.

**Manage suites:**
```text
/sipi-test Show all tests
/sipi-test Show tests tagged smoke
/sipi-test Create a regression suite with app-launch, settings-toggle, and tab-navigation
```

**Quality audits:**
```text
/sipi-test Audit the onboarding and settings screens for accessibility
/sipi-test Check for missing accessibility labels and identifiers
/sipi-test Check onboarding in English, Japanese, and German for translation completeness
/sipi-test Check for untranslated text and text clipping
/sipi-test Compare the profile screen in Light and Dark mode
/sipi-test Check the settings flow at large Dynamic Type sizes
```

## Workspace structure

SimPilot uses a standard directory layout under `.simpilot/`:

```text
.simpilot/
  config.json                  # Project configuration (app bundle ID, build settings)
  tests/                       # Test definitions
    <test-id>.json
  suites/                      # Test suites
    <suite-name>.json
  devices/                     # Device/simulator profiles
    <profile-name>.json
  runs/                        # Test run results (sipi-test)
    <run-id>/
      run.json                 # Run summary
      report.html              # HTML report (open in browser)
      <test-id>/
        result.json            # Test result
        step-NNN.png           # Step screenshots
        recording.mp4          # (if enabled)
  verify/                      # Verification results (sipi-verify)
    <timestamp>_<description>/
      report.html
```

Recommend adding `.simpilot/` (or at least `runs/` and `verify/`) to the project's `.gitignore`.

## Reference

- **[JSON-REFERENCE.md](.claude/skills/sipi-test/references/json-reference.md)** — Complete JSON specification for tests, suites, devices, results, and metadata

## Known limitations

- Non-US text input is entered via the clipboard (paste), not direct per-key typing
- Direct per-key HID typing covers the US keyboard layout
- Simulator only — physical devices are not supported

## Note

This repository is primarily managed by AI. Issues and feedback are welcome, but pull requests are not accepted. If you want to adapt it for your own workflow, please fork it and use your own copy.

## Disclaimer

SimPilot is a development tool. It drives the iOS Simulator through Apple's **undocumented private frameworks**, which Apple may change or remove in any Xcode or macOS update — that can break SimPilot without notice. It is not affiliated with or endorsed by Apple, and is not intended for App Store or production use. It is provided **as-is, without warranty — use at your own risk.**

## License

MIT © 2026 hmhv. See [LICENSE](LICENSE).
