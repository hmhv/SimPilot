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

1. add or correct stable identifiers and labels
2. replace fragile custom interactions with standard controls when local and safe
3. add deterministic seed data, debug hooks, or launch paths that improve repeatability
4. adjust layout or timing only when the root cause is clearly in app code

If the fix is local, low-risk, and improves repeatability without masking a real bug, implement it (see "Implement Directly When"); do not implement changes whose main effect is hiding a defect or making the test pass without improving the product.

## Good Fixes

- add `accessibilityIdentifier` to controls that are hard to target
- replace fragile coordinate-only interaction with a stable identifier
- use standard SwiftUI/UIKit controls instead of custom gesture wrappers when local
- add seed data or a stable initial state for repeatable test setup
- expose a debug-only navigation hook when the production flow is too expensive to repeat

## Avoid

- loosening `verify` conditions without evidence
- adding arbitrary sleeps when the underlying issue is a missing state signal
- changing business behavior only to help tests
- hiding real regressions behind test-specific hacks
- **applying an identifier/label fix without a negative-control check** — before the fix, confirm the test would still FAIL if the feature were actually broken. A fix that makes a broken feature pass is masking a defect, not stabilizing a test

## Implement Directly When

- the identifier or label to add is obvious
- the source change is local and low-risk
- the change improves repeatability without changing product meaning

## Stop And Ask When

- the change affects navigation, analytics, auth, payments, or permissions
- the proposed debug hook has product or security implications
- multiple valid identifiers or labels exist and wording matters
