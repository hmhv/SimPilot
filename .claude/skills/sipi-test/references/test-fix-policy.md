# Test Fix Policy

Use this to decide what to propose and what to change directly.

## When Fixes Are Allowed

Fixes happen only in an explicit FIX phase, **never mid-run**.

- The run that hit the failure is recorded as **FAIL first** — do not edit anything to turn that run green.
- Apply the fix afterward, then **re-run from a clean launch** to confirm it.
- Keep the prior FAIL in the run history; the fix is validated by a new run, not by overwriting the failing one.

## Core Rule

Do not weaken verification just to make a test pass.

Prefer app changes that make the UI more observable and more deterministic.

## Fix Priority

When the root cause is in app code, prefer the smallest useful change, in this order:

1. add a stable `accessibilityIdentifier` when targeting is the only problem
2. correct accessibility labels, hints, or traits when the change improves the released app
3. propose any other source change and wait for explicit approval

Do not add seed data, debug hooks, launch paths, networking switches, or business-logic branches without approval. Explain the smallest change that would make the scenario testable and ask whether to implement it.

## Good Fixes

- add `accessibilityIdentifier` to controls that are hard to target
- replace fragile coordinate-only interaction with a stable identifier
- correct a missing accessibility label or trait that helps actual assistive-technology users

The following can be good proposals, but require approval before implementation:

- replace a custom gesture wrapper with a standard control
- add seed data or a stable initial state
- expose a debug-only navigation or networking hook

## Avoid

- loosening `verify` conditions without evidence
- adding arbitrary sleeps when the underlying issue is a missing state signal
- changing business behavior only to help tests
- hiding real regressions behind test-specific hacks
- **applying an identifier/label fix without a negative-control check** — before the fix, confirm the test would still FAIL if the feature were actually broken. A fix that makes a broken feature pass is masking a defect, not stabilizing a test

## Implement Directly When

- the change is limited to an obvious `accessibilityIdentifier`, including one used only for testing; or
- an accessibility label, hint, or trait change clearly improves the released app

Still keep RUN and FIX separate and preserve the original failing result.

## Stop And Ask When

- any source change is not limited to the accessibility cases above
- the change affects navigation, networking, state injection, seed data, analytics, auth, payments, or permissions
- the proposed debug hook has product or security implications
- multiple valid identifiers or labels exist and wording matters

Use a concrete proposal: "This scenario is not externally controllable. Adding <small change> would make it testable without changing production behavior. Do you want me to implement it?"
