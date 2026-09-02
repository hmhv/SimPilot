# Adverse State and System Event Testing

Use saved simulator-control actions when a UI state depends on something outside
normal touch input. JSON shapes for every control are in `actions.md`; this file
covers what each one actually changes and how to test with it.

## Decision Rules

1. Prefer an external simulator control that changes the real runtime state.
2. Do not modify app source by default.
3. If the state is not externally controllable, describe the smallest app change
   that would expose it and ask before editing. Follow `test-fix-policy.md`.
4. Verify the user-visible result and recovery, not merely that the control
   command succeeded.

## What each control really does

| Control | Effect |
|---|---|
| `privacy` | Grants, revokes, or resets an app-scoped permission before the flow runs |
| `open-url` | Delivers a deep link or universal link through the system |
| `push` | Sends a real Simulator remote-notification payload |
| `location` | Sets or clears a simulated coordinate |
| `appearance`, `content-size`, `increase-contrast` | Change the runtime appearance/accessibility settings |
| `status-bar` | Screenshot chrome only — **not** connectivity, battery, or radio behavior |
| `launch` / `terminate` | Restarts with explicit arguments/environment, or stops the app |
| `network-condition` | Applies an app-scoped profile through an explicitly installed provider |
| `biometrics` | Enrolls/unenrolls Face ID / Touch ID and delivers match / no-match to a live prompt (Xcode 27+) |
| `display-state` | Sets the accessibility appearance facets simctl cannot reach (Xcode 27+) |
| `memory-warning` | Delivers a memory-pressure warning to the running app, so cache eviction and low-memory recovery run on demand (Xcode 27+) |

## What cleanup actually covers

Cleanup runs at the end of the run, and between tests in a suite with
`reset-between-tests` on (the default). It is not uniform — three tiers:

| Tier | Controls | Behavior |
|---|---|---|
| Restored to the captured prior value | `appearance`, `content-size`, `increase-contrast`, `display-state`*, `biometrics` enrollment | Baseline captured before the first write, written back afterward |
| **Cleared, not restored** | `location`, `status-bar`, `network-condition` | Reset to "no override". A value the device already had before the run is NOT put back |
| **Not touched at all** | `privacy`, `open-url`, `push`, `launch`, `terminate` | No cleanup whatsoever |
| Nothing to clean | `memory-warning` | A one-off event the app handles as it arrives; the device holds no state for it |

\* `display-state` restores only facets the runtime reported at capture time, and
the color-filter pair has three ways to slip through:

Which facets matter depends on what the step **changes**. A step that only
toggles the filter never overwrites the stored kind or intensity, so those are
still there afterward and nothing is at risk. The cases below are about a step
that sets `color-filter-type` or `color-filter-intensity`.

The check is **per facet the step changes**, never about the pair as a whole: a
step that sets only `color-filter-type` is not affected by an unreadable
intensity, and one that sets only `color-filter-intensity` is not affected by an
unreadable type.

| Baseline at capture | Outcome |
|---|---|
| Filter **off** | Restore switches it off; the screen is correct whatever kind and intensity are left configured behind it. Only storage is dirty, surfacing the next time anyone enables a filter |
| Filter **on**, and every facet the step changes has a baseline value that can be written back | Fully restored |
| Filter **on**, and a facet the step changes has no reported baseline value, or an intensity outside 0.25…1.0, or is an intensity change against a `grayscale` baseline | **The step is refused before it writes**, naming that facet. Changing something it could not put back is worse than not running the step |

The last row is a deliberate hard failure, and it names the one facet at fault: a
step that only changes the type is never blocked by an unreadable intensity, and
the other way round.

What that failure prevents differs by cause, and the message says which:

- **An unreadable or out-of-range value** would leave the screen itself wrong —
  the filter returns at the run's setting, not the user's. This is what earlier
  builds did silently, reporting a clean run.
- **A `grayscale` baseline** is milder: the kind is restorable, so the screen does
  come back to grayscale. Only the run's intensity persists in storage, surfacing
  later when someone picks a different kind.

Row 1 is the one you can clean up by hand. Restore **only the facets your step
changes** — an untouched facet is still on the device and writing it back is
needless risk. Each has its own condition, because `sipi appearance` refuses an
intensity outside 0.25…1.0 and refuses any intensity alongside `grayscale`:

| Facet your step changes | Capturing helps when |
|---|---|
| `color-filter-type` only | Always — a reported kind can be written back as-is |
| `color-filter-intensity` (alone or with the type) | The stored type is not `grayscale` **and** the stored intensity is within 0.25…1.0 |

Either way the values are readable only while the filter is on, so the capture
starts by turning it on:

```bash
sipi appearance "$UDID" --color-filter on        # makes the stored values readable
sipi appearance "$UDID" --json                   # capture what your step will change
sipi appearance "$UDID" --color-filter off       # REQUIRED: put it back before the run
# ...run the test...
```

Then write back **only** what your step changed. The restore command differs per
facet — do not copy a line for a facet you left alone:

```bash
# changed the type only
sipi appearance "$UDID" --color-filter-type <captured-type>

# changed the intensity only — the type must accompany it, because devicectl
# applies an intensity in the context of a kind; use the CAPTURED type, so this
# writes the original pair rather than introducing a kind the device never had
sipi appearance "$UDID" --color-filter-type <captured-type> --color-filter-intensity <captured-intensity>

# changed both — same command as above
sipi appearance "$UDID" --color-filter-type <captured-type> --color-filter-intensity <captured-intensity>

sipi appearance "$UDID" --color-filter off       # finally, back to off
```

The third line is not optional. Leaving the filter on hands the harness a
baseline of "filter on", which is a different device state than the one you
started from — and it is exactly the baseline the harness may refuse to work
against.

**The only measure that covers all three rows is a disposable simulator.** Run
color-filter work on a device created for it (`simctl create`) and deleted
afterward. That is the standing recommendation; treat manual capture as a
narrow fallback.

The last tier is where suites leak. Each of those actions has a lasting effect
the harness cannot undo, so **write the recovery yourself**:

- `privacy` — authorization has no safe readback. Add an explicit
  `{"type": "privacy", "operation": "reset", …}` step when a later test needs the
  prompt again.
- `open-url` and `push` — these change app state, not just the current screen: a
  badge count, persisted storage, a restored navigation stack, an unread marker.
  A relaunch does not undo any of it. Recovery has to be app-specific — drive the
  app's own reset/clear path, delete the data the event created, navigate back to
  a known screen — and then **verify** the known state rather than assuming it.
  When the app exposes no such path, reinstalling it (`simctl uninstall` +
  `install`) removes the **app container** — see the limits below before relying
  on it.
- `launch` with `arguments` / `environment` — the flags persist for the process's
  lifetime. A later test that assumes a plain launch must `launch` again without
  them.
- `terminate` — leaves the app closed. The next test needs its own `launch`
  unless the run itself relaunches.

A biometric `match` / `no-match` is transient and needs no recovery; only the
enrollment it depends on is restored.

### What reinstalling does and does not clear

`simctl uninstall` + `install` deletes the app's own container — its
`Documents`, `Library`, `tmp`, and `UserDefaults`. It is not a full reset.

**Keychain items can survive an uninstall.** Apple DTS describes the current
behavior as items being left in place, while explicitly calling that an
implementation detail rather than a contract — it is not guaranteed to hold
([Apple Developer Forums thread
36442](https://developer.apple.com/forums/thread/36442)). Either way the
conclusion for testing is the same: a reinstall cannot be relied on to clear
credentials or tokens, so do not treat it as a keychain reset in either
direction. Delete the items the test cares about explicitly.

The same goes for shared containers (an App Group's directory), data owned by an
extension or a sibling app, and anything the app keeps off the device entirely —
server-side records, a synced iCloud store, a push badge the server will re-send.

Reset those explicitly and **verify** the state you expect, rather than treating
reinstall as a clean slate.

### Before reaching for `simctl erase`

`xcrun simctl erase <udid>` destroys **everything on that simulator** — every
installed app, all their data, and all device settings, for every project that
uses it. It is not a test-cleanup step.

Never run it as part of fulfilling an ordinary testing request. Before it is
appropriate, all of these must hold:

1. The user has explicitly approved erasing that specific device.
2. You have echoed the target UDID **and its device name** back to them, and
   confirmed it is not a device they use for anything else.
3. Reinstalling the app afterward is part of the plan — an erased device has no
   app, so every later test fails until it is installed again.

The sequence is `simctl shutdown <udid>` → `erase` → `boot` → reinstall → re-run
preflight.

The standing recommendation is to avoid the question entirely: create a
**dedicated disposable simulator** for adverse-state work (`simctl create`), and
delete it when done. Then a wipe costs nothing and needs no approval.

### Recovery steps do not run after a failure

The harness marks every remaining step **skipped** once a non-optional step
fails. A recovery step written at the end of a test therefore does NOT run on the
test that needed it most — the failing one — and its state leaks into the rest of
the suite. Harness-owned cleanup still runs between tests, but it covers only the
first two tiers above.

Plan around it:

- Put the reset at the **start** of the test that depends on a clean state, not
  at the end of the one that dirtied it.
- Treat a failed adverse-state test as having left the device dirty, and reset
  before re-running rather than trusting the previous run's cleanup.

## Biometric Authentication

A biometric prompt can only be answered while enrollment is on: an unenrolled
device shows the passcode fallback instead, so a `match` has nothing to answer.
Order the steps enroll → reach the prompt → match:

```json
{ "action": { "type": "biometrics", "operation": "enroll" } },
{ "action": { "type": "tap", "selector": { "label": "Sign in with Face ID" } } },
{ "action": { "type": "biometrics", "operation": "match" },
  "verify": { "contains": ["Dashboard"] } }
```

Test the failure path with the same shape and `no-match`, and assert on the app's
own recovery UI (a retry prompt, a passcode fallback), not merely on the absence
of the success screen:

```json
{ "action": { "type": "biometrics", "operation": "no-match" },
  "verify": { "elements": [{ "label": "Try Again" }, { "label": "Dashboard", "exists": false }] } }
```

These need Xcode 27's simulator-capable devicectl; on an older toolchain the step
fails with an explicit message naming the requirement.

## Network Conditions

Run this before authoring an offline test:

```bash
sipi network-condition status
```

If `available` is false, do not claim that SimPilot can make the Simulator offline. Xcode 27 and `simctl` do not expose a simulator-scoped Network Condition API. `simctl status_bar --wifiBars 0` is visual only.

An endpoint refusal or timeout can still validate request-error UI, but it normally leaves `NWPathMonitor` satisfied. Record the tested failure mode accurately:

- connection refused: request failure UI
- timeout/100% loss: timeout, spinner, cancel, retry UI
- path unsatisfied: true reachability/offline UI; requires a provider that changes that observable state or an approved app test hook

When no provider exists, offer one of these choices instead of silently editing code:

- test against a controllable endpoint that refuses or stalls requests
- add an approved test-only endpoint/state hook
- install/configure a simulator network-condition provider

Always include a recovery step: clear the condition, retry, and verify that the success UI returns.

## Provider Contract

Configure an absolute executable path in `.simpilot/config.json`:

```json
{
  "app": "com.example.app",
  "network-condition-provider": "/absolute/path/to/provider"
}
```

Or set `SIPI_NETWORK_CONDITION_PROVIDER`. SimPilot invokes the executable directly without a shell:

```text
provider status --json
provider apply --udid <udid> --bundle-id <bundle-id> --profile <kebab-case-profile>
provider clear --udid <udid> --bundle-id <bundle-id>
```

The provider is responsible for permissions, filtering, and its profile catalog. SimPilot ships no proprietary adapter and no packet filter. A failed automatic clear fails environment cleanup and is reported rather than ignored.

## Error UI Assertions

For an adverse-state step, verify all relevant states:

- the specific error title/message appears
- stale content or the endless loading indicator is absent when appropriate
- retry/cancel controls are reachable
- after recovery, success content appears and the error disappears

Use the normal negative-control rule: the success-path UI must not satisfy the adverse-state verify.
