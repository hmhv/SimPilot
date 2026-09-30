# Verification Workflow

`sipi verify-session` owns every artifact. Do not hand-create the verify
directory, `findings.json`, or the report.

## 1. Understand the change

Read the request, diff, or latest commit and identify the screens to visit, the
behaviors to trigger, the visual states to compare, and the edge cases worth
checking. Read `.simpilot/notes.md` if it exists: it holds this app's known
quirks (§ Project notes in `../../sipi-common/docs/patterns.md`). Appending a
quirk you discover there is allowed — it is a session artifact, not product
source.

## 2. Initialize

```bash
sipi verify-session init "<kebab-case-description>"
```

It prints `Verify results: <absolute path>`. Use that path as `VERIFY_DIR`.

## 3. Capture variants

Capture the same indexed check across all four variants:

```bash
sipi verify-session capture "$VERIFY_DIR" iphone-light "settings-screen" --index 1 --device "$IPHONE_UDID" --appearance light
sipi verify-session capture "$VERIFY_DIR" iphone-dark  "settings-screen" --index 1 --device "$IPHONE_UDID" --appearance dark
sipi verify-session capture "$VERIFY_DIR" ipad-light   "settings-screen" --index 1 --device "$IPAD_UDID"   --appearance light
sipi verify-session capture "$VERIFY_DIR" ipad-dark    "settings-screen" --index 1 --device "$IPAD_UDID"   --appearance dark
```

The command writes aligned filenames such as `001_settings-screen.png` and
updates `checks.json`.

**Run the two device chains in parallel.** The iPhone and iPad chains touch
different UDIDs and are independent, so issue them as two Bash calls in a single
response. Within one device the calls stay sequential — the light and dark
captures share an appearance setting, and interleaving them would race.

Use the same `--index` and check name across variants so the report grid aligns.
Additional checks take the next index.

**On an iPhone Duo, capture both poses and name the variant for each.** It has
two screens — inner 669x951pt when open, cover 466x678pt when shut — and captures
follow whichever is lit, so `duo-light` means nothing on its own. Set the pose,
then capture under a name that says which it is:

```bash
sipi fold "$UDID" --open
sipi verify-session capture "$VERIFY_DIR" duo-open-light "settings-screen" --index 1 --device "$UDID" --appearance light
sipi fold "$UDID" --closed
sipi verify-session capture "$VERIFY_DIR" duo-cover-light "settings-screen" --index 1 --device "$UDID" --appearance light
```

The two poses share one UDID, so unlike the iPhone/iPad chains they must run
sequentially. Put the device back the way you found it when the chain ends —
`sipi fold-state` before the first fold tells you what that was.

### Waiting for a state

Between driving an action and capturing its result, wait for the state rather
than a guessed number of seconds:

```bash
sipi wait-for "$IPHONE_UDID" --label "Saved" --timeout 10        # exit 1 at the deadline
sipi wait-for "$IPHONE_UDID" --text "Loading" --absent --timeout 15
```

It returns the moment the condition holds, and a timeout is itself evidence — the
screen never reached the state — worth a finding rather than a longer sleep.

**Never write a `sleep` you cannot justify with a number you measured.** These are
the measured costs on an M-series host (Xcode 27.2 beta, iPhone 17, iOS 27.2), and
they are what a guessed wait is competing against:

| Step | Measured |
|---|---|
| `describe-ui` | 0.22s |
| `describe-ui --deep` | 1.62s — don't reach for it just to count nodes |
| `screenshot`, `voiceover` | ~0.5s |
| `simctl launch` → tree stops changing | **3.1–3.6s** |
| `shutdown` + `boot` + `bootstatus -b`, warm | **6.8s** (22s on a device's first cold boot) |

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
Prefer it over `--absent` for this: `--absent` is judged against the deep tree, so
each poll costs `--deep` time rather than 0.22s.

Booting is cheap enough to prefer over cleverness. When a simulator is in a state
only a restart clears, restart it — 6.8s warm — instead of hunting for a lighter
reset. Restarting individual simulator daemons does not work: see
`sipi-common/docs/troubleshooting.md`.

### Driving with no `sleep` at all

Every wait in a probe can be a poll on a real signal. The three that usually get
written as sleeps:

```bash
# 1. Relaunching: one call, no "terminate, sleep, launch"
xcrun simctl launch --terminate-running-process "$UDID" "$BID"

# 2. Waiting for the app: poll for the app's OWN content, not for the tree to exist
sipi wait-for "$UDID" --text "Settings" --timeout 12 --interval 0.2

# 3. Waiting for a device-state change: poll the reader, don't guess how long it takes
until [ "$(sipi voiceover "$UDID" --json | grep -o 'true\|false')" = "true" ]; do :; done
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
root `AXLabel` has changed from what it was before the launch, or simply poll for a
string only that app renders.

What is left after that is iOS, not sipi: the app's content appears in the tree at
**~3.5s**, consistently, warm or cold. The screen changes at 1.78s and the
`describe-ui` call spanning the transition itself blocks for ~2.2s.
`UIAnimationDragCoefficient` does not shorten it (3.53s / 3.56s at 0.1 against
3.62s unset — noise). So the way to make a probe faster is **fewer launches**, not
shorter waits: budget ~3.5s for each one and drop the launches the result does not
need. Rewriting a 5-launch probe with guessed sleeps (~4 min) as a 3-launch probe
with these polls brought it to 26.5s for the same conclusions.

### Looking at the screen yourself

`verify-session capture` writes full-size evidence. To look at what a session
captured, `sipi verify-session sheet "$VERIFY_DIR" --device iphone` lays the
captures out as a grid — a row per check, up to three per sheet, light and dark
side by side — and prints each sheet's path, so a whole device is one or two
Reads instead of one per capture. Without `--device` a sheet holds every variant.
Sheets are written to a new temporary directory on every run and never become
part of the verification. For a single screen you are only going to read,
`sipi screenshot "$UDID" look.png --max-pixel 600` is a fraction of the size, and
`sipi describe-ui "$UDID" --format compact` gives the tree as one line per
element. None of these replaces the evidence captures.

### Recording motion (optional)

When the change is only observable in motion — an animation, transition, or
gesture flow — record video as an extra artifact:

```bash
sipi record-video "$IPHONE_UDID" "$VERIFY_DIR/clip.mp4" &   # blocks until SIGINT
REC=$!
# ...perform the flow...
kill -INT "$REC"   # finalizes the H.264 .mp4
```

The report embeds only the PNG grid, and `findings.json` has a fixed
`{check, variant, issue}` schema — neither links the video. Surface the clip path
out-of-band in your final response, alongside the `Verify results:` path, and
mention it inside a finding's `issue` text only when it documents an actual
motion bug. The default flow stays screenshot-first.

## 4. Record findings

```bash
sipi verify-session finding "$VERIFY_DIR" \
  --check "settings-screen" \
  --variant "ipad-dark" \
  --issue "Toggle label is clipped"
```

With no issues, leave `findings.json` as the empty array `init` created — but
first confirm the changed behavior through `describe-ui` when behavior is what
changed. Visual checks can stay screenshot-first.

## 5. Finalize

```bash
sipi verify-session finalize "$VERIFY_DIR" --title "Description"
cat "$VERIFY_DIR/summary.json"

# Add --html and open report.html when a person wants the screenshot grid.
```

Then return the path, and state any skipped variant and why:

```text
Verify results: <absolute path to $VERIFY_DIR>
```
