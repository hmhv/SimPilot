# iOS Accessibility Best Practices

Apple-first reference for making correct accessibility suggestions and source-code fixes.

## Source Basis

Use these Apple sources as the default authority:

- Human Interface Guidelines: Accessibility
- Human Interface Guidelines: VoiceOver
- SwiftUI `accessibilityLabel(_:)`
- UIKit accessibility guidance
- App Store Connect accessibility evaluation criteria for VoiceOver and contrast

## Core Principles

- Prefer semantic accessibility over visual-only workarounds.
- Use simulator observation to find the issue, then use source review to confirm and fix it.
- If visible text is already correct, avoid redundant labels unless the control is custom or ambiguous.
- Keep labels concise. Do not repeat traits that assistive technologies already announce.
- Fix the root cause in code when the change is local and low-risk.

## Labels

Use `accessibilityLabel` when:

- a control is icon-only
- visible text is abbreviated or ambiguous
- a custom element has no meaningful spoken name

Do not:

- append control type in the label when the trait already conveys it
- write instructional prose inside the label when a short name is enough

Good pattern:

- `"Play"` instead of `"Play button"`
- `"Notifications"` instead of `"Tap to open notification settings"`

## Values and State

Expose current state when people need to know it without seeing the screen.

Use accessibility value or state for:

- toggles
- sliders
- steppers
- progress indicators
- selected tabs or filters

If the control already exposes state automatically through SwiftUI or UIKit, avoid duplicating it manually.

## Traits and Roles

Make sure the spoken role matches the actual interaction.

Common corrections:

- interactive `HStack` pretending to be a button -> make it an actual `Button` if possible
- tappable custom view -> ensure accessibility traits identify it as interactive
- headings in long screens -> mark important section titles as headers/headings

Prefer real platform controls over custom gesture wrappers when possible.

## Focus Order and Grouping

VoiceOver should follow the same logical reading order people expect visually.

Fixes to prefer:

- reorder source layout instead of hacking around focus later
- group related content that should be read together
- split overly large containers when grouping hides important controls

When a screen has cards or rows with many subviews:

- decide whether the row should be one combined element or several separate elements
- keep that decision consistent across the screen

## Identifiers

Accessibility identifiers are not a user-facing accessibility feature, but they are valuable for:

- stable automation
- debugging
- inspecting simulator output

Recommend identifiers when:

- automation repeatedly falls back to coordinates
- many similar controls are hard to distinguish
- debugging or audit output is ambiguous

Prefer stable, screen-scoped names like:

- `Settings.notifications-toggle`
- `Profile.edit-button`

## Contrast

Only report contrast when supported by evidence.

Use these rules:

- if a screenshot clearly shows weak text/background separation, report a contrast risk
- if code exposes actual colors, compare them before making a stronger claim
- treat obvious failures as fixes; treat uncertain cases as review items

As a practical baseline, Apple references WCAG-style minimum contrast guidance for text.

## Dynamic Type

Check whether text can scale without clipping, overlap, or truncation that breaks comprehension.

Prefer fixes such as:

- use Dynamic Type-compatible fonts
- remove fixed heights that clip text
- allow wrapping before shrinking
- make containers grow vertically

Avoid fixes that simply clamp text size for accessibility categories unless there is a strong product reason.

## VoiceOver

When reviewing VoiceOver behavior:

- spoken labels should be concise and specific
- focus order should match reading order
- custom controls should expose the right semantics
- important actions should be reachable without guesswork

For custom composite controls, prefer exposing one clear accessible element instead of many noisy sub-elements unless independent interaction is required.

## Preferred Source Fixes

In SwiftUI, common good fixes include:

- `accessibilityLabel(...)`
- `accessibilityValue(...)`
- `accessibilityHint(...)` only when necessary
- `accessibilityIdentifier(...)`
- `accessibilityAddTraits(...)`
- replacing custom tap containers with real `Button`, `Toggle`, or `NavigationLink`

In UIKit, common good fixes include:

- `isAccessibilityElement`
- `accessibilityLabel`
- `accessibilityValue`
- `accessibilityTraits`
- `accessibilityIdentifier`
- `UIAccessibilityElement` for custom drawn controls

## When To Implement Directly

Go ahead and edit source code when:

- the missing label or identifier is obvious
- the control type is clearly wrong
- a fixed frame is obviously causing accessibility text clipping
- the change is local and unlikely to alter product behavior

Stop and ask only when:

- the correct spoken wording is product-sensitive
- grouping/focus behavior affects a complex interaction model
- the change could alter analytics, navigation, or business logic

## Reporting Language

Prefer concrete issue language:

- "Icon-only button has no accessibility label"
- "VoiceOver order reads metadata before primary content"
- "Dynamic Type clips the action label at accessibility sizes"
- "Automation falls back to coordinates because controls lack identifiers"

Prefer concrete fix language:

- "Add `accessibilityLabel(\"Search\")` to the icon button"
- "Mark this title as a heading"
- "Replace fixed height with vertical expansion so text can wrap"
- "Add `accessibilityIdentifier(\"Settings.notifications-toggle\")`"
