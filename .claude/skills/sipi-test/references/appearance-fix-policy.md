# Appearance Fix Policy

Use this to decide what to propose and what to change directly.

## Core Rule

Prefer fixes that preserve readability, hierarchy, and adaptive behavior across modes and text sizes.

## Good Fixes

- replace hard-coded colors with adaptive semantic colors
- remove fixed heights that clip larger text
- allow vertical expansion and wrapping
- adjust spacing when Dynamic Type creates overlap
- use materials or backgrounds that preserve contrast in Dark mode

## Avoid

- treating every visual difference as a bug
- freezing text size to avoid layout work
- using one-off color tweaks that break the opposite appearance
- adding visual hacks that do not solve the underlying adaptive issue

## Implement Directly When

- the issue is clearly visible and local
- the adaptive fix is straightforward
- the change does not alter business logic

## Stop And Ask When

- the visual change affects brand-critical styling
- there are multiple plausible design directions
- the issue suggests a broader design-system decision rather than a local bug
