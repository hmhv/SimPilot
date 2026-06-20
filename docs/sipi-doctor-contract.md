# `sipi doctor` contract

`sipi doctor` is the capability probe that gates the whole `sipi-*` skill
workflow. `preflight.md` runs it before any test/verify step. A DRAFT,
manual-only workflow (`.github/workflows/sipi-doctor-matrix.yml`,
`workflow_dispatch` with a single placeholder Xcode) is *intended* to grow into
a per-Xcode matrix that runs it to catch Apple-version churn once a runner-fleet
decision is made — it is not an active per-Xcode gate today. Because `preflight`
gates on it (and the draft matrix is meant to), the exit-code semantics and the
machine-readable output shape are a **contract** — treat them as a stable
interface, not an implementation detail. The reference implementation is
`Sources/sipi/Doctor.swift`.

## Purpose

Report whether the native driver can actually reach Apple's private Simulator
frameworks on **this** machine / Xcode:

- dlopen status of the three private frameworks (CoreSimulator, SimulatorKit,
  AccessibilityPlatformTranslation),
- presence of the key classes / selectors / symbols each one needs
  (`NSClassFromString`, `respondsToSelector`, `dlsym` results),
- the active Xcode developer dir,
- which simulators (if any) are currently booted.

It performs read-only probing only. It boots nothing, taps nothing, and mutates
no device state.

## Invocation

```
sipi doctor            # human-readable text report
sipi doctor --json     # machine-readable JSON report
```

Both forms write the report to **stdout** and use the same exit code. `--json`
selects the JSON shape below; otherwise a plain-text report is emitted.

## Exit codes

| Exit code | Meaning |
|---|---|
| `0` | **All core capabilities present.** Every core check passed (`allCorePresent == true`). The workflow may proceed. |
| non-zero | **At least one core capability is missing.** `preflight` must stop and surface the failing check(s). |

"Core capabilities" are the three framework checks: `CoreSimulator`,
`SimulatorKit`, and `AccessibilityPlatformTranslation`. The exit code is derived
**only** from these checks (`allCorePresent = checks.allSatisfy { $0.ok }`).
Booted-device discovery is informational and never affects the exit code: a
machine with all frameworks healthy but no booted device still exits `0` (the
skills boot a device separately). Callers that also need a booted device must
check `bootedDevices` themselves.

`preflight.md` gates strictly on the exit code:

```sh
if ! sipi doctor; then
  # stop: native driver cannot reach the private frameworks on this machine
fi
```

## JSON output shape (`--json`)

A single pretty-printed JSON object (`JSONSerialization` with `.prettyPrinted`),
terminated by a newline:

```json
{
  "developerDir" : "/Applications/Xcode.app/Contents/Developer",
  "checks" : [
    {
      "name" : "CoreSimulator",
      "ok" : true,
      "detail" : "loaded (SimServiceContext, SimDevice resolve)"
    },
    {
      "name" : "SimulatorKit",
      "ok" : true,
      "detail" : "loaded (SimDeviceLegacyHIDClient resolves)"
    },
    {
      "name" : "AccessibilityPlatformTranslation",
      "ok" : true,
      "detail" : "AXPTranslator ready (sharedInstance ✓, tokenDelegate proto ✓, macElement ✓, SimDevice transport ✓)"
    }
  ],
  "bootedDevices" : [
    "iPhone 16 Pro (XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX)"
  ],
  "allCorePresent" : true
}
```

### Field contract

| Field | Type | Meaning |
|---|---|---|
| `developerDir` | string | The active Xcode developer dir the probe used (`DEVELOPER_DIR` env override, else the well-known Xcode path). |
| `checks` | array of objects | One entry per core capability, in a stable order: `CoreSimulator`, `SimulatorKit`, `AccessibilityPlatformTranslation`. |
| `checks[].name` | string | Stable capability name (one of the three above). |
| `checks[].ok` | bool | Whether this capability fully resolved. |
| `checks[].detail` | string | Human-readable detail (which class/symbol resolved or why it failed). Informational; do not parse for control flow — gate on `ok` / `allCorePresent`. |
| `bootedDevices` | array of strings | Booted simulators as `"<name> (<udid>)"`. May be empty. Informational only. |
| `allCorePresent` | bool | `true` iff every `checks[].ok` is `true`. Mirrors the exit code: `true` ⇔ exit `0`. |

Consumers should key on `name` + `ok` (and `allCorePresent`), not on array
indices or `detail` text, so the contract survives wording changes in `detail`.
New core checks may be appended to `checks` in future; consumers must tolerate
additional entries.

## Text output shape (default)

A short report to stdout, one capability per line, ending in a `result:` line:

```
sipi doctor
  developer dir: /Applications/Xcode.app/Contents/Developer
  [ok] CoreSimulator: loaded (SimServiceContext, SimDevice resolve)
  [ok] SimulatorKit: loaded (SimDeviceLegacyHIDClient resolves)
  [ok] AccessibilityPlatformTranslation: AXPTranslator ready (sharedInstance ✓, tokenDelegate proto ✓, macElement ✓, SimDevice transport ✓)
  booted devices: iPhone 16 Pro (XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX)
  result: all core capabilities present
```

- Each capability line is `  [ok] <name>: <detail>` when present and
  `  [--] <name>: <detail>` when missing.
- `booted devices:` lists `<name> (<udid>)` entries, or `none`.
- The final `result:` line is `all core capabilities present` (exit 0) or
  `missing core capabilities` (exit non-zero).

The text form is for humans; scripts and CI should use `--json` and gate on the
exit code.

## Stability rules

1. The three core check `name`s are stable identifiers; do not rename them.
2. The exit code reflects `allCorePresent` and **only** the core checks.
3. `bootedDevices` and `detail` are informational; their wording may change.
4. Additions are backward-compatible (new `checks` entries, new top-level
   fields). Removals or renames of the fields above are breaking changes and
   require updating `preflight.md` and this contract together.
