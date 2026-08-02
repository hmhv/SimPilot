# UI Driver

`sipi` is the driver. Call it directly — there is no wrapper layer to define.

Shell state does not persist between Bash calls, so every call that touches the
simulator starts with the two variables it needs:

```bash
SIPI=/Users/you/.local/bin/sipi   # the path preflight printed, verbatim
UDID=<resolved-udid>
```

When preflight resolved a path that is NOT on `PATH`, `"$SIPI"` is mandatory in
every later call — a bare `sipi` is `command not found` there. Other docs write
bare `sipi` for readability; substitute `"$SIPI"` whenever the resolved path is
not on `PATH`.

**Among the UDID-taking driver commands, the UDID position varies** — most take
it first, but four do not:

| Shape | Commands |
|---|---|
| `sipi <cmd> <udid> …` | every driver command in the tables below except the four listed here |
| `sipi <cmd> <arg> <udid>` | `key <keycode>`, `gesture <preset>` |
| `sipi <cmd> --flags… <udid>` | `key-sequence --keycodes`, `key-combo --modifiers --key` |

Workspace and diagnostic commands take **no** UDID positional — `doctor`,
`devices`, `validate <path>`, `run-test <test-path>`, `run-suite`,
`report <run-dir>`, `verify-session`, `open-ui`. Those that need a device take it
as a flag (`run-test --device <udid>`).

`network-condition` is split: `status` takes no UDID, but
`apply <profile> <udid> --bundle-id <id>` and `clear <udid> --bundle-id <id>`
both do.

Run `sipi <cmd> --help` when unsure; the tables below show each exact form.

## Coordinate units

Two flags, never interchangeable:

- `--pixel` — logical points, the same space `describe-ui` reports in `frame`.
  Use this for any coordinate you derived from the tree.
- `--norm` — fractions of the screen, 0…1. Use this for "middle of the screen"
  style targets.

**Only one direction is caught.** `--norm` rejects anything outside 0…1, so
frame-derived points hard-error (`Normalized x=200.0 is out of range`). The
reverse is silent: `--pixel -x 0.5 -y 0.5` is a legal pixel coordinate and taps
the top-left corner. Nothing warns you. Confirm a computed coordinate with
`describe-point` before a blind touch.

## Default path

| Need | Command |
|---|---|
| Read the screen | `"$SIPI" describe-ui "$UDID"` |
| Tap by label / id | `"$SIPI" tap "$UDID" --label "Sign In"` / `--id auth.sign-in` |
| Tap a derived coordinate | `"$SIPI" tap "$UDID" --pixel -x 200 -y 700` |
| Put text in a field | `"$SIPI" set-text "$UDID" "text" --id <id>` |
| Press a key | `"$SIPI" key 40 "$UDID"` |
| Capture the screen | `"$SIPI" screenshot "$UDID" out.png` |

`describe-ui` reads the frontmost app tree. Pass `--expect "Text"` when a later
grep is looking for specific text: on a miss it auto-escalates to the deeper grid
pass, which also surfaces System UI (PhotosPicker, Share Sheet,
SFSafariViewController). `--deep` forces that pass unconditionally, for
inspection only.

Selector taps (`--label` / `--id` / `--value`, and `sipi slider`) escalate to the
deep tree on their own, so they reach System UI without `--deep`. Prefer observed
UI over guessing from source, and re-read after each meaningful action when
behavior is flaky.

## Input and gestures

| Need | Command |
|---|---|
| Swipe | `"$SIPI" swipe "$UDID" --norm --start-x .5 --start-y .8 --end-x .5 --end-y .2` |
| Scroll / system edge swipe | `"$SIPI" gesture scroll-down "$UDID"` — presets `scroll-{up,down,left,right}`, `swipe-from-{left,right,top,bottom}-edge` |
| Precise drag (reorder, handle) | `"$SIPI" drag "$UDID" --norm --start-x .. --start-y .. --end-x .. --end-y .. --steps 60` |
| Long press | `"$SIPI" touch "$UDID" --pixel -x .. -y .. --down --up --delay 1.5` |
| Double tap | `"$SIPI" double-tap "$UDID" --label "Map"` (or `--pixel -x .. -y ..`) |
| Pinch / zoom | `"$SIPI" pinch "$UDID" out` (zoom in) / `in` (zoom out) |
| Two-finger non-pinch (rotation) | `"$SIPI" multitouch "$UDID" <phase> x1 y1 x2 y2` — phase `1` begin/move, `2` end |
| Slider to a value | `"$SIPI" slider "$UDID" --label "Volume" --value 75` |
| Hardware button | `"$SIPI" button "$UDID" home` |
| Modifier combo / keycode burst | `"$SIPI" key-combo --modifiers 227 --key 4 "$UDID"` / `"$SIPI" key-sequence --keycodes 11,8,15 "$UDID"` |
| Rotate | `"$SIPI" orientation "$UDID" --set landscape-left` |
| Digital Crown | `"$SIPI" crown "$UDID" <delta>` (watchOS only) |
| What is at this coordinate? | `"$SIPI" describe-point "$UDID" --pixel -x .. -y ..` |

`double-tap` and `pinch` send the composed gesture the guest recognizes; two
separate `tap` calls or hand-assembled `multitouch` phases do not reliably
produce one. `pinch` accepts `--center-x/--center-y`, `--separation`,
`--duration`, and `--steps`.

`describe-point` returns a one-element array, or `[]` when nothing is hit — use
it to confirm a computed coordinate before a blind `touch`.

Text entry: `set-text` is the default and `type` is for when the keystrokes
themselves are under test. The rule and its exceptions live in
`patterns.md` § Text Input.

## Inspection and device state

| Need | Command | Needs Xcode 27 |
|---|---|:---:|
| Mechanical accessibility pass | `"$SIPI" a11y-audit "$UDID"` | — |
| Face ID / Touch ID | `"$SIPI" biometrics "$UDID" <status\|enroll\|unenroll\|match\|no-match>` | Yes |
| Accessibility appearance facets | `"$SIPI" appearance "$UDID" [--reduce-motion on …]` | Yes |
| VoiceOver | `"$SIPI" voiceover "$UDID" [--enable\|--disable]` | Yes |

`appearance` and `voiceover` read the current state when given no flag and write
when given one. `biometrics` is different: the operation is a **required
positional**, and reading is the explicit `status` operation. All three say so
explicitly when the toolchain is too old (see
`troubleshooting.md`). Matching a biometric does nothing while the device is
unenrolled.

`a11y-audit` works on any supported Xcode. It reports undersized touch targets,
unlabeled controls, ambiguous duplicate labels, meaningless labels, and truncated
text. Only `missing-label` is an error — it is decidable; the rest are warnings
because they are inferences from the tree. Label rules cover DISABLED controls
too (VoiceOver still announces them); the touch-target rule does not (they cannot
be tapped). It runs the deep grid pass by default (~1s per screen) so System UI
and overlays are audited too — `--fast` skips it. It exits non-zero on an
error-severity finding, so it can gate a check directly; `--fail-on none`
inspects without failing, `--json` gives structured output, `--rules` runs a
subset, `--min-touch-target` changes the 44pt threshold. An empty accessibility
tree is a hard error rather than a clean report, so "no findings" always means
the screen was actually inspected.
