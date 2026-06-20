# Accessibility Audit

Use the native `sipi` UI driver (via the `ui_*` helpers) to inspect screens on the iOS Simulator and produce a concrete issue list by screen. Simulator observation is the primary source of truth; source code review is supplementary for confirming root cause and implementing fixes.

Read `../references/a11y-best-practices.md` before proposing fixes or editing code.

Judge whether each screen is semantically correct for assistive technology users: the right thing is announced, in the right order, with the right role and state. Use a skeptical audit mindset - identify weaknesses, do not excuse them.

## Scope

- missing `accessibilityLabel`
- missing or weak `accessibilityIdentifier`
- likely reading-order problems
- tap targets or controls that are hard to distinguish from nearby content
- rough contrast checks when color values or screenshots make it obvious

## Workflow

1. Confirm preflight is complete.
2. Ask the app to navigate screen by screen or run the user-provided flow.
3. For each screen:
   - run `ui_describe`
   - capture `ui_screenshot`
   - inspect element roles, labels, identifiers, and ordering
4. When the issue is unclear from simulator output alone, inspect the relevant source code.
5. Record issues by screen in a report.
6. For each issue, suggest the smallest practical fix. Apply it directly when it meets the Fix Priority criteria below.

## Fix Priority

Prefer fixes in this order:

1. incorrect or missing semantic label/value/trait
2. incorrect focus order or grouping
3. missing identifier that blocks stable automation or debugging
4. insufficient contrast or Dynamic Type breakage
5. custom control behavior that should be exposed through accessibility APIs

If a fix is local, low-risk, and clearly aligned with Apple guidance, implement it instead of only reporting it.
Do not soften findings just because a workaround exists for testers or developers.

## Report Format

Use this shape:

```text
Screen: settings
- severity: high
  issue: Toggle has no accessibilityLabel
  evidence: AX element shows empty label
  fix: add .accessibilityLabel("Notifications")
```

## Difference From Xcode Accessibility Audit

- Works on arbitrary simulator flows, not only test code that already exists
- Produces AI-written remediation suggestions
- Can inspect multiple screens in one pass
- Can pair UI tree inspection with screenshots and source review

## Guardrails

- Do not claim a contrast failure unless the evidence is visible from screenshot or code
- Do not invent missing labels; mark them as suggestions
- Prefer specific fixes over generic accessibility advice
- Use Apple platform guidance as the default tie-breaker when multiple fixes seem possible

## Known platform patterns

### Tab Bar (iOS 18+)

The floating tab bar in iOS 18+ exposes an `AXGroup` with `AXLabel: "Tab Bar"` but **zero children** in `sipi describe-ui`. Individual tab items have no `AXLabel`.

**Detection**: When you find a `Tab Bar` group with no children or children without labels, report it as:
- severity: medium
- issue: Tab bar items have no accessibility labels
- evidence: `AXGroup "Tab Bar"` has 0 children in describe-ui
- fix: Add `.accessibilityLabel("TabName")` to each `Tab` in the SwiftUI `TabView`

### Coordinate-based navigation for tabs

When tab items cannot be tapped by label, use coordinate-based tapping. See `../../sipi-common/docs/patterns.md` "Tab Switching" for device-specific coordinates and methods.

## System UI scope

The following system-provided UI runs in a separate process. It is inspectable with `ui_describe` when the native bridge is available, but it is not app-owned UI. Do not report missing labels as app accessibility defects unless the app supplies or configures that content:

- **ColorPicker** - system color picker sheet
- **PhotosPicker** - system photo library picker
- **FileImporter / fileExporter** - document browser
- **ShareLink** - system share sheet
- **ASWebAuthenticationSession** - Safari web authentication
- **System alerts** - permission dialogs (camera, location, etc.)

When encountering these, note in the report: "System UI - outside app audit scope" and move to the next screen unless the task explicitly asks to audit the app-to-system flow.
