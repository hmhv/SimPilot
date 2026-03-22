# Test Fix Policy

Use this to decide what to propose and what to change directly.

## Core Rule

Do not weaken verification just to make a test pass.

Prefer app changes that make the UI more observable and more deterministic.

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

## Implement Directly When

- the identifier or label to add is obvious
- the source change is local and low-risk
- the change improves repeatability without changing product meaning

## Stop And Ask When

- the change affects navigation, analytics, auth, payments, or permissions
- the proposed debug hook has product or security implications
- multiple valid identifiers or labels exist and wording matters
