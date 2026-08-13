# Accessibility Audit

Inspect screens on the simulator and produce a concrete issue list per screen.
Simulator observation is the source of truth; source review confirms root cause
and implements fixes. Be skeptical — expose weaknesses, do not explain them away.

Read `../references/a11y-best-practices.md` before proposing fixes or editing
code.

The question for each screen: does assistive technology announce the right thing,
in the right order, with the right role and state?

## Scope

- missing `accessibilityLabel`
- missing or weak `accessibilityIdentifier`
- likely reading-order problems
- tap targets or controls hard to distinguish from nearby content
- rough contrast checks when color values or screenshots make it obvious

## Workflow

1. Complete preflight.
2. Navigate screen by screen, or run the user-provided flow.
3. Per screen:
   - `sipi a11y-audit "$UDID" --fail-on none --json` first — it settles the
     mechanical rules so your judgment can go to what a machine cannot decide
   - `sipi describe-ui "$UDID" --expect "<text you expect here>"` — the fast tree
     auto-escalates to the deep grid pass, surfacing System UI, only on a miss
   - `sipi screenshot "$UDID" <path>`
   - inspect element roles, labels, identifiers, and ordering
4. When simulator output alone leaves the issue unclear, read the source.
5. Record issues per screen.
6. Suggest the smallest practical fix for each; apply it directly when it meets
   the Fix Priority criteria below.

### Mechanical rules vs. judgment

`sipi a11y-audit` reports what is decidable from the tree, with a frame and a
label on every finding. Take those verbatim — do not re-derive or soften them.
Reserve your own analysis for what it deliberately does not decide:

- reading and focus order
- whether a present label is CORRECT for what the control does (the audit only
  catches labels that are meaningless on their face)
- grouping, custom rotors, and custom actions
- contrast and clipped text, which need pixel analysis. The `truncated-text` rule
  only catches clipping the guest itself reports with an ellipsis, and it exempts
  an actionable element's LABEL because Apple's own convention puts a trailing
  ellipsis on any control that opens a further prompt ("Save As…"). A clipped
  BUTTON label is therefore yours to spot
- whether an undersized `hit-region` finding is real: the accessibility frame is
  a lower bound on the tappable area, so a 20pt glyph inside a 44pt control
  reports as undersized. That rule warns rather than errors for this reason

Run the pass under real accessibility settings, not only the defaults — several
defects appear nowhere else (Xcode 27+):

```bash
sipi appearance "$UDID" --json                 # capture the baseline FIRST
sipi appearance "$UDID" --reduce-motion on --reduce-transparency on --show-borders on
sipi appearance "$UDID" --larger-accessibility-sizes on --text-size accessibility-extra-large
sipi voiceover "$UDID" --enable
```

Restore what you changed when the pass is done — **except VoiceOver.** On iOS 27
turning it back off leaves the device unable to report an accessibility tree for
any app that comes to the foreground afterwards, and only a restart clears it. So
enable VoiceOver LAST, and end the session with a device restart rather than
`--disable`:

```bash
xcrun simctl shutdown "$UDID" && xcrun simctl boot "$UDID"
```

See `../../sipi-common/docs/troubleshooting.md` → "`describe-ui` returns a single
empty root".

## Fix Priority

1. incorrect or missing semantic label / value / trait
2. incorrect focus order or grouping
3. missing identifier that blocks stable automation or debugging
4. insufficient contrast or Dynamic Type breakage
5. custom control behavior that should be exposed through accessibility APIs

Implement a fix rather than only reporting it when it is local, low-risk, and
clearly aligned with Apple guidance. Do not soften findings because a workaround
exists for testers or developers.

## Report Format

```text
Screen: settings
- severity: high
  issue: Toggle has no accessibilityLabel
  evidence: AX element shows empty label
  fix: add .accessibilityLabel("Notifications")
```

## Difference from Xcode's accessibility audit

`XCUIApplication.performAccessibilityAudit` only runs from inside a UI test
target — there is no simctl or devicectl subcommand that audits a running app,
and Accessibility Inspector is GUI-only. This pass instead:

- runs from the command line against any booted simulator, with no test target
  and no change to the app under test
- works on arbitrary flows, not only on test code that already exists
- produces written remediation suggestions
- inspects multiple screens in one pass, pairing the tree with screenshots and
  source review
- drives the accessibility settings the audit should run under

What Xcode's audit still does that this does not: contrast ratio and clipped-text
detection, both of which need pixel analysis of the rendered frame. Run Xcode's
audit from a UI test in addition when those matter.

## Guardrails

- Do not claim a contrast failure unless the evidence is visible in a screenshot
  or in code
- Do not invent missing labels; mark them as suggestions
- Prefer specific fixes over generic accessibility advice
- Use Apple platform guidance as the tie-breaker when several fixes seem possible

## Known platform patterns

### Tab bar (iOS 18+)

The floating tab bar exposes an `AXGroup` labeled `Tab Bar` with **zero
children**; individual tab items have no `AXLabel`. Report it as:

- severity: medium
- issue: Tab bar items have no accessibility labels
- evidence: `AXGroup "Tab Bar"` has 0 children in describe-ui
- fix: add `.accessibilityLabel("TabName")` to each `Tab` in the `TabView`

For navigating tabs that cannot be tapped by label, see
`../../sipi-common/docs/patterns.md` § Tab Switching.

## System UI scope

The following runs in a separate process and is surfaced only by the deep grid
pass (`describe-ui --deep`, or `--expect "<text>"` to escalate on a miss). Even
when surfaced it is not app-owned UI — do not report missing labels there as app
defects unless the app supplies or configures that content:

ColorPicker, PhotosPicker, FileImporter / fileExporter, ShareLink,
ASWebAuthenticationSession, and system permission alerts.

Note "System UI — outside app audit scope" and move on, unless the task
explicitly asks to audit the app-to-system flow.
