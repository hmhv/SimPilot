// TextEntryProbe.swift
//
// Decides whether text entry actually landed.
//
// `sipi type` reaches the guest through HID (a Cmd+V paste or keystrokes), and a
// simulator whose keyboard HID has stopped being delivered swallows all of it
// while every call still succeeds. Reporting `ok` there is worse than failing: a
// saved test goes green while the app never saw the input.
//
// Measured 2026-08-01: this tracks DEVICE age, not the iOS runtime. A freshly
// created device types fine on iOS 27.0; long-lived ones stop delivering
// keyboard events on both iOS 27.0 and 26.4, and neither `simctl erase` nor a
// reboot brings them back — only recreating the device does.
//
// The naive check, "did the accessibility tree change", does not work: the status
// bar clock is in the tree, so the tree changes every second whether or not the
// text arrived. This narrows the comparison to the only thing that must change —
// the CONTENT of the text-entry elements on screen.
//
// Pure Foundation: no SimBridge, no private frameworks, fully unit-testable.

import Foundation

public enum TextEntryProbe {
    /// A fingerprint of every text-entry element's identity and current content,
    /// or nil when the screen has no text-entry element at all.
    ///
    /// nil is a meaningful answer, not an error: it means there was nowhere for
    /// the text to go, which is itself a reason to fail the step rather than
    /// report success.
    ///
    /// Identity is included alongside the value so that replacing one field with
    /// another holding the same text still reads as a change.
    public static func fingerprint(roots: [AXNode]) -> String? {
        let fields = roots.flatMap { $0.flattened() }.filter(\.isTextEntry)
        guard !fields.isEmpty else { return nil }
        return fields.map { field in
            [
                field.AXUniqueId ?? "",
                field.AXLabel ?? "",
                field.AXValue ?? ""
            ].joined(separator: "\u{0}")
        }.joined(separator: "\n")
    }

    /// Why a text-entry attempt should be considered a no-op, or nil when it
    /// evidently landed.
    ///
    /// `before` and `after` come from `fingerprint`. A nil `before` means the
    /// screen had no field to type into; an unchanged fingerprint means the
    /// keystrokes never reached the field that was there.
    public static func failureReason(before: String?, after: String?) -> Reason? {
        guard let before else { return .noTextEntryElement }
        // A field that disappeared between the two reads (the keyboard dismissed,
        // a sheet closed) is a change, not a no-op.
        guard let after else { return nil }
        return before == after ? .unchanged : nil
    }

    public enum Reason: Equatable, Sendable {
        /// No text-entry element was on screen, so there was nowhere to type.
        case noTextEntryElement
        /// A text-entry element was on screen and its content did not change.
        case unchanged

        public var message: String {
            switch self {
            case .noTextEntryElement:
                return """
                    no text field is on screen, so the text had nowhere to go. Tap the field first \
                    so it holds focus. If the app takes keyboard input through a view that exposes \
                    no text-entry element (a game, a custom canvas), pass --no-verify.
                    """
            case .unchanged:
                return """
                    the text field's content did not change, so the keystrokes never arrived. The \
                    usual cause is a simulator that has stopped delivering keyboard HID — paste, \
                    --keyboard and --clear are all ignored on such a device. This tracks device age, \
                    not the iOS version, and survives both `simctl erase` and a reboot: create a \
                    replacement device with `simctl create` to confirm. Meanwhile `sipi set-text` \
                    writes the value through the accessibility bridge and needs no keyboard at all. \
                    A field can also be unfocused: tap it first. Pass --no-verify to skip this check.
                    """
            }
        }
    }
}
