# Appearance Verification

Use the native `sipi` UI driver (via the `ui_*` helpers) and `xcrun simctl ui` to compare the same screens across appearance and text-size variants. Simulator observation is the primary source of truth; source code review is supplementary for understanding constraints and applying fixes.

Read `../references/appearance-fix-policy.md` before proposing or applying source-code changes.

Judge whether each variant is semantically correct: readable, correctly emphasized, and still communicating the intended action and state. Use a skeptical review mindset - catch visual regressions, do not explain them away.

## Workflow

1. Decide the target screens and variants:
   - Light / Dark
   - Dynamic Type sizes to compare
2. Keep device and orientation fixed.
3. For each variant:
   - switch appearance or content size category
   - relaunch if needed
   - navigate to the same screen
   - capture `ui_screenshot`
   - inspect `ui_describe`
4. Compare captures and identify regressions.
5. If needed, inspect relevant view code to confirm root cause. Apply fixes that meet the Fix Priority criteria below.

## Fix Priority

Prefer fixes in this order:

1. clipping or overlap that breaks readability
2. contrast issues that make content hard to perceive
3. incorrect adaptive colors or materials
4. fixed sizing that breaks Dynamic Type
5. decorative differences that obscure important controls

If the fix is local, visible, and low-risk, implement it instead of only reporting it.
Do not rely on cosmetic hacks whose only purpose is making the screenshot look acceptable without fixing the underlying adaptive issue.

## Appearance Commands

To switch appearance or content size on the simulator:

```bash
xcrun simctl ui <UDID> appearance dark
xcrun simctl ui <UDID> appearance light
xcrun simctl ui <UDID> content_size extra-large
xcrun simctl ui <UDID> content_size accessibility-extra-extra-extra-large
```

If appearance does not switch, reboot the simulator:

```bash
xcrun simctl shutdown <UDID> && xcrun simctl boot <UDID>
```

## Checks

- low-contrast content in Dark mode
- icons or separators disappearing against the background
- clipped text at larger Dynamic Type sizes
- buttons or cards overlapping at larger text sizes
- content no longer reachable without scrolling

## Output

Report findings by screen and variant:

```text
Screen: profile
Variant: dark / accessibility-extra-large
- clipping: subtitle overlaps action button
- contrast-risk: secondary text blends into card background
```

## Guardrails

- Do not mark a screenshot difference as a bug unless it hurts readability or layout integrity
- Keep screenshots aligned by capturing the same state before comparing
- Prefer concrete visual evidence over general design opinions
