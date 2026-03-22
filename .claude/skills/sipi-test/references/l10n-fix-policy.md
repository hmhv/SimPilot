# Localization Fix Policy

Use this to decide what to propose and what to change directly.

## Core Rule

Fix the source of the localization issue, not just the visible symptom.

## Good Fixes

- add the missing localized string
- correct a wrong localization key reference
- unify inconsistent terminology across nearby screens
- remove fixed widths or heights that cause clipping in some languages
- let text wrap before shrinking or truncating important meaning

## Avoid

- shortening text in one locale only to hide a layout bug unless that wording is actually better
- forcing a locale through runtime hacks when the app resource setup is wrong
- changing product terminology without consistency across the app

## Implement Directly When

- the translation omission is obvious
- the wrong key or fallback is clear in code/resources
- the clipping issue is caused by a local frame or layout constraint

## Stop And Ask When

- marketing or legal wording differs by locale
- the correct translation depends on domain knowledge you do not have
- terminology should be aligned with product or brand decisions
