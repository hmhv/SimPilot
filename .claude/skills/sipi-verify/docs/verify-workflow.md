# Verification Workflow

Use `sipi verify-session` for all artifacts. Do not hand-create the verify directory, `findings.json`, or report.

## 1. Understand the Change

Read the user request, diff, or latest commit and identify:

- Screens to visit
- Behaviors to trigger
- Visual states to compare
- Edge cases worth checking

## 2. Initialize Session

```bash
sipi verify-session init "<kebab-case-description>"
```

The command prints:

```text
Verify results: <absolute path>
```

Use that path as `VERIFY_DIR`.

## 3. Capture Variants

Capture the same indexed check across variants:

```bash
sipi verify-session capture "$VERIFY_DIR" iphone-light "settings-screen" --index 1 --device "$IPHONE_UDID" --appearance light
sipi verify-session capture "$VERIFY_DIR" iphone-dark  "settings-screen" --index 1 --device "$IPHONE_UDID" --appearance dark
sipi verify-session capture "$VERIFY_DIR" ipad-light   "settings-screen" --index 1 --device "$IPAD_UDID" --appearance light
sipi verify-session capture "$VERIFY_DIR" ipad-dark    "settings-screen" --index 1 --device "$IPAD_UDID" --appearance dark
```

The command writes aligned filenames such as `001_settings-screen.png` and updates `checks.json`.

### Recording motion (optional)

When the change is only observable in motion (animation, transition, gesture flow), record video as an extra artifact:

```bash
sipi record-video "$IPHONE_UDID" "$VERIFY_DIR/clip.mp4" &   # blocks until SIGINT
REC=$!
# ...perform the flow with the ui_*/native_* helpers...
kill -INT "$REC"   # finalizes the H.264 .mp4
```

The verify `report.html` embeds only the PNG grid and `findings.json` has a fixed `{check, variant, issue}` schema — neither links the video. Surface the clip path **out-of-band** in your final response (alongside the `Verify results:` path), and mention it inside a finding's free-text `issue` only when it documents an actual motion bug. Keep the default screenshot-first flow unchanged.

## 4. Record Findings

For every issue:

```bash
sipi verify-session finding "$VERIFY_DIR" \
  --check "settings-screen" \
  --variant "ipad-dark" \
  --issue "Toggle label is clipped"
```

If no issues are found, leave `findings.json` as the empty array created by `init`.

Before leaving it empty, confirm the changed behavior through `describe-ui` when behavior matters. Visual checks can remain screenshot-first.

## 5. Finalize

```bash
sipi verify-session finalize "$VERIFY_DIR" --title "Description"
open "$VERIFY_DIR/report.html"
```

Return:

```text
Verify results: <absolute path to $VERIFY_DIR>
```

## Notes

- Use the same `--index` and check name across variants so the report grid aligns.
- Add extra checks with the next index.
- Skipped variants must be explained in the final response.
