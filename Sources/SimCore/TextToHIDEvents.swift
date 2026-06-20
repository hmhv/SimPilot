// TextToHIDEvents.swift
//
// Adapted for SimPilot from AXe (https://github.com/cameroncooke/AXe),
// origin: Sources/AXe/Utilities/TextToHIDEvents.swift — MIT License
// (Copyright (c) 2025 Cameron Cooke; see THIRD_PARTY_LICENSES.md).
//
// AXe emits FBSimulatorControl `[FBSimulatorHIDEvent]`. SimCore is FB-free, so
// the same key-down/key-up sequence is produced as Foundation-only
// `HIDKeyEvent` values (a USB HID usage code plus a down/up flag); the driver
// layer feeds these to the native HID injector. The conversion algorithm and
// the Left Shift usage code (225) are reproduced verbatim.
//
// NOTE: KeyCode's table assumes a US keyboard layout, so characters outside it
// are unsupported here. The CLI handles non-US text through a `simctl pbcopy` +
// Cmd+V path.

import Foundation

/// One raw HID key event: a USB HID usage code and whether it is a press
/// (`down == true`) or a release.
public struct HIDKeyEvent: Equatable, Sendable {
    public let usage: Int
    public let down: Bool

    public init(usage: Int, down: Bool) {
        self.usage = usage
        self.down = down
    }
}

public enum TextToHIDEvents {
    /// USB HID usage code for Left Shift.
    public static let leftShiftUsage = 225

    public enum TextConversionError: Error, CustomStringConvertible, Equatable {
        case unsupportedCharacter(Character)

        public var description: String {
            switch self {
            case .unsupportedCharacter(let char):
                return "No keycode found for character: '\(char)'"
            }
        }
    }

    /// Key down + key up for a character that does not require shift.
    private static func simpleKeyEvent(keyCode: Int) -> [HIDKeyEvent] {
        return [
            HIDKeyEvent(usage: keyCode, down: true),
            HIDKeyEvent(usage: keyCode, down: false)
        ]
    }

    /// Left-Shift-wrapped key down + key up for a character that requires shift.
    private static func shiftedKeyEvent(keyCode: Int) -> [HIDKeyEvent] {
        return [
            HIDKeyEvent(usage: leftShiftUsage, down: true),   // Left Shift down
            HIDKeyEvent(usage: keyCode, down: true),          // Target key down
            HIDKeyEvent(usage: keyCode, down: false),         // Target key up
            HIDKeyEvent(usage: leftShiftUsage, down: false)   // Left Shift up
        ]
    }

    /// Converts a single character to its corresponding HID events.
    private static func eventsForCharacter(_ character: Character) throws -> [HIDKeyEvent] {
        let charString = String(character)
        let keyEvent = KeyEvent.keyCodeForString(charString)

        guard keyEvent.keyCode != 0 else {
            throw TextConversionError.unsupportedCharacter(character)
        }

        if keyEvent.shift {
            return shiftedKeyEvent(keyCode: keyEvent.keyCode)
        } else {
            return simpleKeyEvent(keyCode: keyEvent.keyCode)
        }
    }

    /// Whether every character in `text` maps to a supported HID usage code.
    public static func validateText(_ text: String) -> Bool {
        for character in text {
            let charString = String(character)
            let keyEvent = KeyEvent.keyCodeForString(charString)
            if keyEvent.keyCode == 0 {
                return false
            }
        }
        return true
    }

    /// Converts a text string to a flat sequence of HID key events.
    /// - Throws: `TextConversionError.unsupportedCharacter` for any character
    ///   outside the US-keyboard table.
    public static func convertTextToHIDEvents(_ text: String) throws -> [HIDKeyEvent] {
        var events: [HIDKeyEvent] = []
        for character in text {
            events.append(contentsOf: try eventsForCharacter(character))
        }
        return events
    }
}
