# Appearance Verification

Compare the same screens across appearance and text-size variants. Simulator
observation is the source of truth; source review explains constraints and
applies fixes. Be skeptical — catch visual regressions, do not explain them away.

Read `../references/appearance-fix-policy.md` before proposing or applying source
changes.

The question for each variant: is it readable, correctly emphasized, and still
communicating the intended action and state?

## Workflow

1. Decide the target screens, the light/dark pair, and the Dynamic Type sizes.
2. Keep device and orientation fixed.
3. Per variant: switch appearance or content size → relaunch if needed →
   navigate to the same screen → `sipi screenshot` → `sipi describe-ui --expect
   "<text you expect in this variant>"` (escalates to the deep pass only on a
   miss).
4. Compare captures and identify regressions.
5. Read the view code when needed to confirm root cause; apply fixes that meet
   the Fix Priority below.

## Switching appearance

```bash
xcrun simctl ui "$UDID" appearance dark
xcrun simctl ui "$UDID" appearance light
xcrun simctl ui "$UDID" content_size extra-large
xcrun simctl ui "$UDID" content_size accessibility-extra-extra-extra-large
```

If appearance does not switch: `xcrun simctl shutdown "$UDID" && xcrun simctl boot "$UDID"`.

The remaining accessibility facets have no simctl equivalent and go through
`sipi appearance` (Xcode 27+, which checks for the toolchain and says so):

```bash
sipi appearance "$UDID" --json                     # capture the baseline FIRST
sipi appearance "$UDID" --reduce-motion on
sipi appearance "$UDID" --reduce-transparency on
sipi appearance "$UDID" --larger-accessibility-sizes on --text-size accessibility-extra-large
sipi appearance "$UDID" --color-filter on --color-filter-type deuteranopia --color-filter-intensity 0.8
sipi appearance "$UDID" --liquid-glass-opacity 1.0  # opaque; 0.0 is fully translucent
```

These are ad-hoc commands with no automatic restore, unlike the saved-test
`display-state` action — read the baseline first and write it back when done.

**VoiceOver is not part of this pass.** Setting it is retired (as is the
`voiceover` test action): on iOS 27, turning it off after it has been on empties
every app's accessibility tree until the device restarts, and turning it on does
not change what `describe-ui` reports. `sipi voiceover "$UDID"` still reads the
state — useful when a device's tree looks wrong because someone left VoiceOver on.

The colour filter is the exception you cannot generally undo. `--json` reports
the type and intensity only while the filter is on, and writing them back goes
through `sipi appearance`, which refuses an intensity outside 0.25…1.0 and
refuses any intensity alongside `grayscale`.

Restore only the facets you changed — an untouched one is still on the device.
Each has its own condition:

| Facet you changed | Can you put it back? |
|---|---|
| `--color-filter` on/off only | Yes. Nothing else was overwritten |
| `--color-filter-type` | Yes, if you captured the previous kind first |
| `--color-filter-intensity` | Only if the stored type is not `grayscale` and the stored intensity was within 0.25…1.0. Otherwise it cannot be written back and your value persists |

The capture procedure — including turning the filter back off before the run — is
in `../references/adverse-state-testing.md`. These are ad-hoc commands with no
automatic restore, so nothing stops you here; the saved-test `display-state`
action refuses the step outright in the cases it could not undo.

Since some cases cannot be repaired at all, **run colour-filter work on a
disposable simulator** (`simctl create`, delete when done) rather than on a
device whose settings anyone depends on.

For the **light/dark** portion, `verify-session` can own the aligned capture and
the report:

```bash
sipi verify-session capture "$VERIFY_DIR" <variant> "<check>" --index N --appearance light|dark
```

It forces the appearance with a built-in settle, and `finalize` renders the
iPhone/iPad × light/dark grid — the same engine as `/sipi-verify`. Dynamic Type
still needs the `content_size` commands above; `--appearance` cannot set it.

## Checks

- low-contrast content in Dark mode
- icons or separators disappearing against the background
- clipped text at larger Dynamic Type sizes
- buttons or cards overlapping at larger text sizes
- content no longer reachable without scrolling

## Fix Priority

1. clipping or overlap that breaks readability
2. contrast issues that make content hard to perceive
3. incorrect adaptive colors or materials
4. fixed sizing that breaks Dynamic Type
5. decorative differences that obscure important controls

Implement rather than only report when the fix is local, visible, and low-risk.
Do not use cosmetic hacks whose only effect is making the screenshot acceptable
while the adaptive issue remains.

## Output

```text
Screen: profile
Variant: dark / accessibility-extra-large
- clipping: subtitle overlaps action button
- contrast-risk: secondary text blends into card background
```

## Guardrails

- A screenshot difference is not a bug unless it hurts readability or layout
  integrity
- Keep screenshots aligned by capturing the same state before comparing
- Prefer concrete visual evidence over general design opinions
