# Localization Verification

Switch languages, capture screens, and compare localized output. Simulator
observation is the source of truth; source review finds untranslated strings and
fixes them at the origin. Be skeptical — expose localization weaknesses, do not
rationalize them away.

Read `../references/l10n-fix-policy.md` before proposing or applying source
changes.

The question for each locale: does the wording match the intended meaning, is
terminology consistent, and does the layout still communicate the right action
and hierarchy?

## Workflow

1. Decide the locale list and target screens.
2. Per locale: switch the simulator language → relaunch the app → navigate to
   each screen → `sipi describe-ui "$UDID" --expect "<expected localized string>"`
   → `sipi screenshot "$UDID" <path>`.
3. Compare locale outputs for untranslated labels, mixed-language strings,
   clipped or off-screen text, and layout regressions.
4. When the cause is not obvious from the simulator, inspect source strings,
   localization tables, and the relevant UI code. Apply fixes that meet the Fix
   Priority below.

`--expect` confirms presence only. It does not assert absence and does not change
the exit code, so keep the manual scan in step 3 for the untranslated and clipped
checks.

## Language switching

Drive `Settings.app` with `sipi`:

```bash
xcrun simctl launch "$UDID" com.apple.Preferences
```

Then navigate: General → Language & Region → "Add Language…" or the current
language → target language → confirm. Accept any continue/restart prompt and let
the simulator settle.

Relaunch the target app before capturing:

```bash
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null
xcrun simctl launch "$UDID" "$BUNDLE_ID"
```

Example locales: English (US), Japanese, French, German, Chinese Simplified,
Chinese Traditional.

Use `simctl` only to launch, reboot, or recover from a stuck language change. Do
not use `simctl boot` flags or `LANG` environment variables as the primary
locale-switching method.

### Settings navigation notes

- Prefer visible labels in `Settings.app`.
- The Settings hierarchy shifts across iOS versions — re-read with `describe-ui`
  before tapping.
- Record the exact path that worked for the current runtime in the report.
- If the switch path is too unstable, inspect the localization resources first
  and return to the simulator for final verification.

## Checks

- label still in the source language
- placeholder or button text longer than its visible frame
- frame extending past screen bounds
- the same screen diverging materially between locales without intent

## Fix Priority

1. missing translation or wrong localization key
2. text clipping caused by local layout constraints
3. inconsistent terminology across locales
4. fallback-to-source-language issues in code or resource loading

Implement the source fix rather than only reporting it when the issue is local
and unambiguous. Do not accept mixed-language, clipped, or misleading output on
the grounds that a user could probably infer the meaning.

## Output

```text
Locale: ja
Screen: onboarding-step-2
- untranslated: "Get Started"
- clipping-risk: primary button width exceeds visible area
```

## Guardrails

- A string is not wrong merely because it is shorter or longer
- Treat truncation as a likely issue, not a guaranteed bug, until a screenshot
  confirms it
- Keep one device and orientation fixed while comparing locales
