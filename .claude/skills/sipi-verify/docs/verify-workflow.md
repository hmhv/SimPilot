# Verification Workflow

`sipi verify-session` owns every artifact. Do not hand-create the verify
directory, `findings.json`, or the report.

## 1. Understand the change

Read the request, diff, or latest commit and identify the screens to visit, the
behaviors to trigger, the visual states to compare, and the edge cases worth
checking.

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
open "$VERIFY_DIR/report.html"
```

Then return the path, and state any skipped variant and why:

```text
Verify results: <absolute path to $VERIFY_DIR>
```
