# Verification Workflow

## 1. Understand the Change

Determine what was changed and what needs to be verified.

### If context is provided by the user
- Use the description to identify affected screens, components, and behaviors
- Read relevant source files if needed for deeper understanding

### If no context is provided (auto-detect)
- Run `git diff HEAD` or `git diff --cached` to see recent changes
- If no uncommitted changes, check `git log -1 --stat` for the latest commit
- Identify which screens and components are affected from the changed files
- If the changes are unclear, ask the user what to verify

### Output of this step
A mental checklist:
- Which screen(s) to navigate to
- What behavior to trigger
- What the expected result should be
- Any edge cases worth checking (empty state, invalid input, boundary values)

## 2. Plan Checks

State the plan briefly before executing. Example:

```
Verification plan:
1. Navigate to Settings screen → confirm new toggle appears
2. Toggle on → verify label changes to "Enabled"
3. Toggle off → verify it reverts
4. Kill and relaunch → verify state persisted

Variants: iPhone light/dark, iPad light/dark
```

Keep it short — 3-7 check items is typical. Don't over-plan; this is exploratory.

## 3. Build & Install

If source code was modified (the common case after implementing/fixing):

1. Follow `../../sipi-common/docs/build.md` to rebuild
2. Install on both iPhone and iPad simulators
3. Prepare the output directory (see `report.md` for structure)

If only verifying an already-installed app, skip the build.

## 4. Execute Checks

Run the same checks across all 4 variants in this order:

1. **iPhone + light** → all check items → save screenshots to `iphone-light/`
2. **iPhone + dark** → switch appearance → same checks → save to `iphone-dark/`
3. **iPad + light** → boot iPad, switch to light → same checks → save to `ipad-light/`
4. **iPad + dark** → switch appearance → same checks → save to `ipad-dark/`

### Per-variant procedure

At the start of each variant, set the device and appearance:

```bash
UDID=<device-udid>
xcrun simctl ui $UDID appearance light  # or dark
sleep 2
```

Also include the `../../sipi-common/docs/ui-driver.md` shell prelude in this same Bash call before the first UI operation.

For each check item:

1. **Navigate** to the relevant screen
   - Use `ui_describe` to confirm current location
   - Navigate using the fallback chain from `../../sipi-test/docs/patterns.md`

2. **Perform the action**
   - Trigger the behavior being verified
   - Allow time for animations (`sleep 1-2`)

3. **Capture screenshot**
   - `ui_screenshot "$VERIFY_DIR/<variant>/NNN_<description>.png"`
   - Use zero-padded 3-digit numbering: `001`, `002`, ...
   - Description in kebab-case: `001_settings-screen.png`, `002_toggle-on.png`
   - Same numbering and names across all 4 variants

4. **Observe and note**
   - Read the screenshot to assess visual correctness
   - Use `ui_describe` when element state needs confirmation
   - Note any issues found for the report

### Screenshot naming

Screenshots must use the same number and name across all variants so the report can align them in a grid:

```
iphone-light/001_settings-screen.png
iphone-dark/001_settings-screen.png
ipad-light/001_settings-screen.png
ipad-dark/001_settings-screen.png
```

### Adapt as you go

This is exploratory — if you notice something unexpected while checking, investigate it. Add extra screenshots as needed (they'll appear in the report as extra rows).

## 5. Record Findings

Before generating the report, write `findings.json` in the verify directory. This file drives the report status badge and prevents reporting "All OK" when issues exist.

```bash
# No issues found — write empty array
echo '[]' > "$VERIFY_DIR/findings.json"

# Issues found — write array of objects
cat > "$VERIFY_DIR/findings.json" << 'EOF'
[
  { "check": "toggle-on", "variant": "ipad-dark", "issue": "toggle label clipped" }
]
EOF
```

The report script reads `findings.json` to auto-determine the status badge:
- Empty array `[]` → "All OK"
- Non-empty array → "Issues Found"
- Missing file + `--status ok` → prints a warning (status is caller-asserted without verification)
- Missing file + no flag → defaults to "Issues Found" (fail-safe)

## 6. Generate Report

After all 4 variants are complete and findings are recorded, generate `report.html`:

```bash
SKILL_ROOT="$HOME/.agents/skills/sipi-verify"
[ -d "$SKILL_ROOT" ] || SKILL_ROOT="$HOME/.claude/skills/sipi-verify"
swift "$SKILL_ROOT/scripts/generate_verify_report.swift" "$VERIFY_DIR" --title "Description"
open "$VERIFY_DIR/report.html"
```

Do not pass `--status ok` manually. Let the script read `findings.json` to determine the status. The `--status` flag exists only as a fallback when `findings.json` cannot be written.

The script reads screenshots from each variant directory and generates a comparison grid. See `report.md` for the template reference if manual adjustments are needed.

## 7. Summarize and Return Results

After opening the report, provide a brief summary **and output the result path**:

1. **Output the result path** (required — calling skills depend on this):
   ```
   Verify results: <absolute path to $VERIFY_DIR>
   ```

2. **Summarize findings**:
   - **All OK**: "Verification complete — all 4 variants look good. Report opened in browser."
   - **Issues found**: list each issue with which variant(s) are affected
   - **Regression candidate**: if the verified behavior is worth protecting, suggest `/sipi-test create`
