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
   - run `ui_a11y_audit --fail-on none --json` first — it decides the mechanical rules for you (undersized touch targets, unlabeled controls, ambiguous duplicate labels, meaningless labels, truncated text) so the judgment below can focus on what a machine cannot decide
   - run `ui_describe --expect "<text you expect on this screen>"` so the fast tree auto-escalates to the deep grid pass (surfacing System UI) only when the expected text is missing
   - capture `ui_screenshot`
   - inspect element roles, labels, identifiers, and ordering
4. When the issue is unclear from simulator output alone, inspect the relevant source code.
5. Record issues by screen in a report.
6. For each issue, suggest the smallest practical fix. Apply it directly when it meets the Fix Priority criteria below.

### Mechanical rules vs. judgment

`sipi a11y-audit` reports what is decidable from the tree, with a frame and a
label on every finding. Take those verbatim — do not re-derive or soften them.
Reserve your own analysis for what it deliberately does not decide:

- reading and focus order
- whether a present label is CORRECT for what the control does (the audit only
  catches labels that are meaningless on their face)
- grouping, custom rotors, and custom actions
- contrast and clipped text, which need pixel analysis — the audit's
  `truncated-text` rule only catches clipping the guest itself reports with an
  ellipsis, and it exempts an actionable element's LABEL because Apple's own
  convention puts a trailing ellipsis on any control that opens a further prompt
  ("Save As…"). A clipped BUTTON label is therefore yours to spot
- whether an undersized `hit-region` finding is real: the accessibility frame is
  a lower bound on the tappable area, so a 20pt glyph inside a 44pt control
  reports as undersized. That rule warns rather than errors for this reason

Run the pass under real accessibility settings rather than only the defaults.
`ui_appearance --reduce-motion on --reduce-transparency on --show-borders on`,
`ui_appearance --larger-accessibility-sizes on --text-size accessibility-extra-large`,
and `ui_voiceover --enable` each change what the app renders and announces;
several defects only appear in those states. Restore what you changed afterward
(read the state with a bare `ui_appearance` first).

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

Xcode's `XCUIApplication.performAccessibilityAudit` only runs from inside a UI
test target — there is no simctl or devicectl subcommand that audits a running
app, and Accessibility Inspector is GUI-only. This pass:

- Runs from the command line against any booted simulator, with no test target
  and no changes to the app under test
- Works on arbitrary simulator flows, not only test code that already exists
- Produces AI-written remediation suggestions
- Can inspect multiple screens in one pass
- Can pair UI tree inspection with screenshots and source review
- Can drive the accessibility settings the audit should run under
  (`ui_appearance`, `ui_voiceover`) in the same pass

What Xcode's audit still does that this does not: contrast ratio and clipped-text
detection, both of which need pixel analysis of the rendered frame. When those
matter, run Xcode's audit from a UI test in addition to this pass.

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

The following system-provided UI runs in a separate process. It is only surfaced by the deep grid pass (`ui_describe --deep`); the default fast `ui_describe` shows the frontmost app tree only. To check for a specific system control without the full deep cost, use `ui_describe --expect "<text>"`, which auto-triggers the deep pass on a miss. Even when surfaced, it is not app-owned UI. Do not report missing labels as app accessibility defects unless the app supplies or configures that content:

- **ColorPicker** - system color picker sheet
- **PhotosPicker** - system photo library picker
- **FileImporter / fileExporter** - document browser
- **ShareLink** - system share sheet
- **ASWebAuthenticationSession** - Safari web authentication
- **System alerts** - permission dialogs (camera, location, etc.)

When encountering these, note in the report: "System UI - outside app audit scope" and move to the next screen unless the task explicitly asks to audit the app-to-system flow.
