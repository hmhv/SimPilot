# Localization Verification

Use the native `sipi` UI driver (via the `ui_*` helpers) and the iOS Simulator Settings app to switch languages, capture screens, and compare localized UI output. Simulator observation is the primary source of truth; source code review is supplementary for finding untranslated strings and fixing issues at the source.

Read `../references/l10n-fix-policy.md` before proposing or applying source-code changes.

Judge whether each localized UI is semantically correct: the wording matches the intended meaning, terminology is consistent, and the layout still communicates the right action and hierarchy. Use a skeptical review mindset - expose localization weaknesses, do not rationalize them away.

## Workflow

1. Decide the locale list and target screens.
2. For each locale:
   - switch simulator language in `Settings.app`
   - relaunch the app
   - navigate to each target screen
   - run `ui_describe`
   - save `ui_screenshot`
3. Compare locale outputs for:
   - untranslated labels
   - mixed-language strings
   - clipped or off-screen text
   - layout regressions between locales
4. If the root cause is not obvious from the simulator, inspect source strings, localization tables, and relevant UI code. Apply fixes that meet the Fix Priority criteria below.

## Language Switching

Language switching is primarily done by operating `Settings.app` with the native `sipi` UI driver (`ui_*` helpers).

Preferred flow:

1. Launch Settings:

```bash
xcrun simctl launch <UDID> com.apple.Preferences
```

2. Navigate with the `ui_*` helpers through:
   - `General`
   - `Language & Region`
   - `Add Language...` or current language
   - choose the target language
   - confirm the language change

3. If iOS asks to continue or restart apps, accept it and wait for the simulator to settle.

4. Terminate and relaunch the target app before capturing:

```bash
xcrun simctl terminate <UDID> <BUNDLE_ID> 2>/dev/null
xcrun simctl launch <UDID> <BUNDLE_ID>
```

Example target locales: `English (US)`, `Japanese`, `French`, `German`, `Chinese, Simplified`, `Chinese, Traditional`.

Use `simctl` only as a helper for launching apps, rebooting the simulator, or recovering from a stuck language change. Do not rely on `simctl boot` flags or `LANG` environment variables as the primary locale-switching method.

## Settings Navigation Notes

- Prefer visible labels in `Settings.app` first
- If the Settings hierarchy changes across iOS versions, re-check with `ui_describe` before tapping
- Record the exact path that worked for the current simulator runtime in the report or note
- If the locale switch path is too unstable, inspect source localization files first and then return to the simulator for final verification

## Checks

- Label still appears in source language
- Placeholder or button text is longer than its visible frame
- Frame extends past screen bounds
- Same screen diverges materially between locales without intent

## Fix Priority

Prefer fixes in this order:

1. missing translation or wrong localization key
2. text clipping caused by local layout constraints
3. inconsistent terminology across locales
4. fallback-to-source-language issues in code or resource loading

If the issue is local and unambiguous, implement the source fix instead of only reporting it.
Do not accept mixed-language, clipped, or misleading output just because a user could probably infer the meaning.

## Output

Summarize findings by locale and screen:

```text
Locale: ja
Screen: onboarding-step-2
- untranslated: "Get Started"
- clipping-risk: primary button width exceeds visible area
```

## Guardrails

- Do not assume a string is wrong just because it is shorter or longer
- Treat truncation as a likely issue, not a guaranteed bug, unless the screenshot confirms it
- Keep one simulator device and orientation fixed while comparing locales
