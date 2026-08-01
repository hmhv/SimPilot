# Adverse State and System Event Testing

Use saved simulator-control actions when a UI state depends on something outside normal touch input.

## Decision Rules

1. Prefer an external simulator control that changes the real runtime state.
2. Do not modify app source by default.
3. If the state is not externally controllable, describe the smallest app change that would expose it and ask before editing. Follow `test-fix-policy.md`.
4. Verify the user-visible result and recovery, not only that a control command succeeded.

## Supported Controls

- `privacy`: grant, revoke, or reset an app-scoped permission before exercising the app flow.
- `open-url`: deliver a deep link or universal link through the system.
- `push`: send a real Simulator remote-notification payload.
- `location`: set or clear a simulated coordinate.
- `appearance`, `content-size`, `increase-contrast`: change accessibility/appearance runtime settings.
- `status-bar`: create deterministic screenshot chrome only. It does not change connectivity, battery state, or radio behavior.
- `launch` and `terminate`: restart with explicit arguments/environment or stop the app.
- `network-condition`: use an explicitly installed provider to apply an app-scoped profile.
- `biometrics`: enroll/unenroll Face ID / Touch ID and deliver a match or no-match to a live prompt (Xcode 27+).
- `display-state`: set the accessibility appearance facets simctl cannot reach — reduce motion, reduce transparency, show borders, color filter and its type/intensity, Liquid Glass opacity, Larger Accessibility Sizes (Xcode 27+).
- `voiceover`: turn VoiceOver on or off for an accessibility pass (Xcode 27+).

The harness restores appearance, content size, Increase Contrast, location, status-bar overrides, active network conditions, the `display-state` facets, VoiceOver, and biometric enrollment after the run, and — in a suite with `reset-between-tests` enabled (the default) — between tests as well, so this state does not leak from one test into the next. Privacy changes cannot be safely read back and are not automatically restored; add an explicit reset step when the next test needs a prompt.

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
