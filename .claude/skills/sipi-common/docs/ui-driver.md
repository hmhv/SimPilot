# UI Driver

`sipi` is the driver. Call it directly — there is no wrapper layer to define.

Shell state does not persist between Bash calls, so every call that touches the
simulator starts with the two variables it needs:

```bash
SIPI=/Users/you/.local/bin/sipi   # the path preflight printed, verbatim
UDID=<resolved-udid>
```

**Among the UDID-taking driver commands, the UDID position varies** — most take
it first, but four do not:

| Shape | Commands |
|---|---|
| `sipi <cmd> <udid> …` | every driver command in the tables below except the four listed here |
| `sipi <cmd> <arg> <udid>` | `key <keycode>`, `gesture <preset>` |
| `sipi <cmd> --flags… <udid>` | `key-sequence --keycodes`, `key-combo --modifiers --key` |

Diagnostic commands take **no** UDID positional — `doctor`, `devices`,
`open-ui`.

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
| Read the screen | `"$SIPI" describe-ui "$UDID" --format compact` — one element per line, ~4-5x fewer bytes than JSON |
| Read the screen as JSON (for grep / `--expect`) | `"$SIPI" describe-ui "$UDID"` |
| Wait for a state instead of sleeping | `"$SIPI" wait-for "$UDID" --label "Dashboard" --timeout 10` (also `--id`, `--value`, `--text`, `--absent`) |
| Tap by label / id | `"$SIPI" tap "$UDID" --label "Sign In"` / `--id auth.sign-in` |
| Tap a derived coordinate | `"$SIPI" tap "$UDID" --pixel -x 200 -y 700` |
| Put text in a field | `"$SIPI" set-text "$UDID" "text" --id <id>` |
| Press a key | `"$SIPI" key 40 "$UDID"` |
| Capture the screen | `"$SIPI" screenshot "$UDID" out.png` — add `--max-pixel 600` when you are going to look at it yourself |
| Which screen a foldable is showing | `"$SIPI" fold-state "$UDID"` — read only; see `foldables.md` |

`describe-ui` reads the frontmost app tree. Pass `--expect "Text"` when a later
grep is looking for specific text: on a miss it auto-escalates to the deeper grid
pass, which also surfaces System UI (PhotosPicker, Share Sheet,
SFSafariViewController). `--deep` forces that pass unconditionally, for
inspection only.

Selector taps (`--label` / `--id` / `--value`, and `sipi slider`) escalate to the
deep tree on their own, so they reach System UI without `--deep`. Prefer observed
UI over guessing from source, and re-read after each meaningful action when
behavior is flaky.

`--format compact` prints the same tree as one line per element —
`Button "Sign In" id="auth.sign-in" frame=(24,88,168,44) hit=(108,110)`, with
`disabled` / `offscreen` only when true — for scanning a screen and picking a
selector. The JSON form is the contract `--expect` reads; use it whenever a
later grep depends on the exact shape.

`wait-for` polls until a condition holds and exits 0, or exits 1 at `--timeout`
(default 10s) with the last unmet reason. It takes exactly one of `--label`,
`--id`, `--value` (exact match with surrounding whitespace trimmed on both
sides, optionally narrowed with `--element-type`) or `--text` (verbatim
substring anywhere in the tree), and `--absent` inverts it. Absence is judged
against the deep tree, presence escalates to it on a miss. Reach for it after
any action whose result lands asynchronously — a navigation, a network round
trip, an alert appearing or dismissing — instead of a guessed `sleep`. A
hand-driven probe built from 5–10s sleeps is where the wall clock actually goes,
not in sipi; § Waiting has the measured costs and the patterns.

`screenshot --max-pixel N` downscales the PNG so its longest side is at most N
pixels. A device-native capture is 3x and costs a reader far more than the
detail is worth; 600 is plenty to judge a layout. Leave it off when the image
itself is the deliverable.

`record-video` runs until it is signalled: start it in the background and stop it
with `kill <pid>` (or `kill -INT`); it finalizes the file before exiting.

`screenshot` and `record-video` both capture whichever screen the device is
lighting. On a device with one screen — every device but iPhone Duo — there is
nothing to choose and `--display` never needs mentioning.

## Waiting

`wait-for` returns the moment the condition holds, and a timeout is itself
evidence — the screen never reached the state — worth reporting rather than
retrying with a longer sleep.

**Never write a `sleep` you cannot justify with a number you measured.** These are
the measured costs on an M-series host (Xcode 27.2 27B52, iPhone 18 Pro, iOS 27.2 24B8117), and
they are what a guessed wait is competing against:

| Step | Measured |
|---|---|
| `describe-ui` | 0.36s |
| `describe-ui --deep` | 2.0s — don't reach for it just to count nodes |
| `screenshot` | 0.36s |
| `voiceover` | 0.15s |
| `simctl launch` → tree stops changing | **1–4s** |
| `shutdown` + `boot` + `bootstatus -b`, warm | **3.1s** |

A run built from 5–10s guesses spends most of its wall clock asleep: the same
VoiceOver experiment took about 4 minutes with guessed sleeps and 42s written
against these numbers, for identical results.

To confirm a state is *still absent* — a screen that must stay broken, empty, or
unreachable — reuse the positive `wait-for` and treat its timeout as the verdict:

```bash
# exit 1 == the app never became readable, which is the result being verified
sipi wait-for "$UDID" --text "Settings" --timeout 6 --interval 0.25
```

That bounds the wait at the timeout and still returns early if the state recovers.
While the text stays missing, each poll also runs the deep pass (~2s), as
`--absent` would, and the interval is added after every miss.

Booting is cheap enough to prefer over cleverness. When a simulator is in a state
only a restart clears, restart it — 3.1s warm — instead of hunting for a lighter
reset. Restarting individual simulator daemons does not work: see
`troubleshooting.md`.

### Driving with no `sleep` at all

Every wait in a probe can be a poll on a real signal. The two that usually get
written as sleeps:

```bash
# 1. Relaunching: one call, no "terminate, sleep, launch"
xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID"

# 2. Waiting for the app: poll for the app's OWN content, not for the tree to exist
sipi wait-for "$UDID" --text "Settings" --timeout 12 --interval 0.2
```

**Poll for content the app itself renders — never for a node count.** `describe-ui`
reports whichever app is frontmost and does not say which one that is. Traced on
iOS 27.2, `simctl launch` returns in 0.19s and the app process is listed
immediately, but **SpringBoard stays frontmost for about 2.3s** and answers the
first ~10 reads with its own status-bar tree. A "wait until nodes > 1" loop passes
there, on the wrong app, about 1.3s before the app has drawn anything — and the
node count does not even differ (SpringBoard and Settings both read 4 root
children through the transition).

The root node's `AXLabel` is the cheap discriminator: it is the frontmost app's
display name, `" "` for the home screen. Traced across one launch:

```
t=0.40s .. 1.99s   rootAXLabel=' '     <- still SpringBoard
t=3.49s onward     rootAXLabel='設定'   <- the app is finally frontmost
```

So when a probe must be sure it is reading the app it just launched, poll until the
root `AXLabel` is that app's display name — a relaunch passes through `" "` on
the way — or simply poll for a string only that app renders.

What is left after that is iOS, not sipi: the app's content appears in the tree
within **~4s** (the table above). The screen changes at 1.78s and the
`describe-ui` call spanning the transition itself blocks for ~2.2s.
`UIAnimationDragCoefficient` does not shorten it (3.53s / 3.56s at 0.1 against
3.62s unset — noise). So the way to make a probe faster is **fewer launches**, not
shorter waits: budget ~4s for each one and drop the launches the result does not
need. Rewriting a 5-launch probe with guessed sleeps (~4 min) as a 3-launch probe
with these polls brought it to 26.5s for the same conclusions.

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
| Digital Crown | `"$SIPI" crown "$UDID" <delta>` (watchOS only; a negative delta goes after `--`: `crown "$UDID" -- -2`) |
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

| Need | Command |
|---|---|
| Mechanical accessibility pass | `"$SIPI" a11y-audit "$UDID"` |
| Face ID / Touch ID | `"$SIPI" biometrics "$UDID" <status\|enroll\|unenroll\|match\|no-match>` |
| Accessibility appearance facets | `"$SIPI" appearance "$UDID" [--reduce-motion on …]` |
| VoiceOver (read only) | `"$SIPI" voiceover "$UDID"` |
| Memory-pressure warning to a running app | `"$SIPI" memory-warning "$UDID" --bundle-id <id>` (or `--pid`) |

`appearance` reads the current state when given no flag (`--json` applies to the
read only) and writes when given
one. `voiceover` only reads: setting it is retired, because on iOS 27 turning it
off after it has been on empties the accessibility tree of every app launched
afterwards until the device restarts, and turning it on changes nothing
`describe-ui` can see. `biometrics` is different again: the operation is a
**required positional**, and reading is the explicit `status` operation. Matching
a biometric does nothing while the device is unenrolled.

`memory-warning` delivers what Simulator.app's Debug menu used to: the app gets
`didReceiveMemoryWarning` and the matching notification, so cache eviction and
low-memory recovery can be exercised on demand. It is transient — nothing to
restore — and fails plainly when the app is not running. Device Hub has no such
control, and neither does simctl.

`a11y-audit` works on any supported Xcode. It reports undersized touch targets,
unlabeled controls, ambiguous duplicate labels, meaningless labels, and truncated
text. Only `missing-label` is an error — it is decidable; the rest are warnings
because they are inferences from the tree. The missing-label and generic-label
rules cover DISABLED controls too (VoiceOver still announces them); the
hit-region (touch-target) and duplicate-label rules do not. It runs the deep
grid pass by default (~2s per screen) so System UI
and overlays are audited too — `--fast` skips it. It exits non-zero on an
error-severity finding, so it can gate a check directly; `--fail-on none`
inspects without failing, `--json` gives structured output, `--rules` runs a
subset, `--min-touch-target` changes the 44pt threshold. An empty accessibility
tree is a hard error rather than a clean report, so "no findings" always means
the screen was actually inspected.

## Foldables (iPhone Duo)

On an iPhone Duo, read `foldables.md` before the first interaction: it has two
screens, and several commands behave differently on each.
