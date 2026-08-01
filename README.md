# SimPilot

Translations: **English** | [日本語](README.ja.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [Español](README.es.md) | [한국어](README.ko.md) | [Português do Brasil](README.pt-BR.md)

SimPilot is a set of agent skills for iOS app testing and verification on the iOS Simulator, driven by natural language requests in Claude Code or Codex.

The top-level README is translated. Skill docs and code remain in English.

## What it does

- **`/sipi-test`** — UI and adverse-state test automation on the iOS Simulator. The skill turns natural-language intent into explicit v2 JSON specs, then `sipi run-test` / `sipi run-suite` executes them with a deterministic harness. Saved tests can control permissions, deep links, push notifications, location, appearance, Dynamic Type, Increase Contrast, Face ID / Touch ID, VoiceOver, the wider accessibility appearance settings, launch environment, and an explicitly configured network-condition provider.
- **`/sipi-verify`** — Post-implementation verification on the iOS Simulator. `sipi verify-session` owns screenshots, findings, and report generation.

Results are saved in `.simpilot/` with HTML reports for browser viewing.

## Prerequisites

- macOS 15 or later
- Xcode 26 or later — needed at **runtime** to drive the Simulator (SimPilot loads Xcode's private Simulator frameworks). Not needed to install. Xcode 27 or later additionally enables Face ID / Touch ID, VoiceOver, and the accessibility appearance settings, which go through `xcrun devicectl`.
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
/sipi-test Create a test that sets the brightness slider to 80% and toggles notifications
/sipi-test Create a test from the current screen
```

Saved tests drive the full interaction surface — taps, double-taps, toggles, sliders, gestures, drags, long-press, pinch and raw multi-touch, key combos, and rotation — as deterministic steps, not just taps and swipes.

They can also create real Simulator-controlled error preconditions such as denied permissions, deep links, push delivery, simulated coordinates, Face ID / Touch ID match and no-match, VoiceOver, the full accessibility appearance surface (reduce motion, reduce transparency, color filters, Liquid Glass opacity), and provider-backed offline/latency profiles. SimPilot does not bundle or imitate a proprietary network conditioner: check `sipi network-condition status` before using a network profile.

Verification goes past text matching: alongside `contains` / `absent` and regular expressions, a step can assert about elements themselves — that a control is disabled, that a list holds exactly five rows, that a value matches a pattern, or that a touch target meets 44pt.

**Run tests:**
```text
/sipi-test Run the settings-navigation test
/sipi-test Run the regression suite
/sipi-test Run tests tagged smoke
/sipi-test Run the regression suite on iPhone 16 Pro
/sipi-test Run tests on iPhone 16 and iPhone 15
/sipi-test Run tests with the regression-profile device set
```

Test execution is handled by the deterministic `sipi` harness. Build/install the app before running, or point `config.json` at an already-installed bundle ID.

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
/sipi-test Audit this screen with Reduce Motion and a color filter on
```

`sipi a11y-audit` runs the mechanical part from the command line against any
booted simulator — undersized touch targets, unlabeled controls, ambiguous
duplicate labels, meaningless labels, truncated text — and exits non-zero on an
error-severity finding, so it can gate CI. Xcode's own accessibility audit only
runs from inside a UI test target.

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
      summary.json             # Compact agent/CI summary
      report.html              # HTML report (open in browser)
      <test-id>/
        result.json            # Test result
        trace.jsonl            # Per-test event trace
        step-NNN.png           # Step screenshots
        step-NNN.describe-before.json
        step-NNN.describe-after.json
        recording.mp4          # (if enabled)
  verify/                      # Verification results (sipi-verify)
    <timestamp>_<description>/
      checks.json
      findings.json
      report.html
```

Recommend adding `.simpilot/` (or at least `runs/` and `verify/`) to the project's `.gitignore`.

## Reference

- **[JSON-REFERENCE.md](.claude/skills/sipi-test/references/json-reference.md)** — Complete JSON specification for tests, suites, devices, results, and metadata

## Known limitations

- Text entry defaults to writing the field's accessibility value (`set-text`), which needs no keyboard and takes any script. Keystroke-level entry (`type`) pastes through the clipboard by default; direct per-key HID typing covers the US keyboard layout only
- **A long-lived simulator can stop delivering keyboard HID** (measured on Xcode 27.0 beta 4): paste, per-key typing, and select-all+delete are all ignored while touch still works. This follows device age rather than the iOS version, and neither `simctl erase` nor a reboot revives it — create a replacement device. `type` detects the condition and fails rather than reporting success; `set-text` is unaffected
- Face ID / Touch ID, VoiceOver, and the accessibility appearance facets beyond light/dark need Xcode 27 — they go through `xcrun devicectl`, which only targets simulators from that release on
- Contrast ratios and clipped text are out of scope for `sipi a11y-audit`; both need pixel analysis of the rendered frame
- Simulator only — physical devices are not supported

## Note

This repository is primarily managed by AI. Issues and feedback are welcome, but pull requests are not accepted. If you want to adapt it for your own workflow, please fork it and use your own copy.

## Disclaimer

SimPilot is a development tool. It drives the iOS Simulator through Apple's **undocumented private frameworks**, which Apple may change or remove in any Xcode or macOS update — that can break SimPilot without notice. It is not affiliated with or endorsed by Apple, and is not intended for App Store or production use. It is provided **as-is, without warranty — use at your own risk.**

## License

MIT © 2026 hmhv. See [LICENSE](LICENSE).
