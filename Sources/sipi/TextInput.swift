// TextInput.swift
//
// Shared text-entry policy for `sipi type` and the saved-test harness. The
// default inserts text by copying it onto the simulator pasteboard and pressing
// Cmd+V, which is independent of the guest keyboard layout and active input
// language/IME — exactly the things that make US-layout HID keystrokes flaky.
// Keyboard injection stays available as an explicit opt-in for the rare field
// that must receive real per-character keystrokes.

import Foundation
import SimCore
import SimShell

/// How `type` text reaches the focused field.
enum TextInputMethod: String {
    /// Copy onto the simulator pasteboard and press Cmd+V. Layout/IME independent.
    case paste
    /// Inject US-keyboard HID keystrokes. Requires US-representable text.
    case keyboard
}

struct TextInputError: Error, CustomStringConvertible {
    let description: String
}

enum TextInput {
    /// Insert `text` into the focused field (first responder). `paste` (the
    /// default) clobbers and restores the simulator pasteboard on a best-effort
    /// basis; `keyboard` requires US-keyboard-representable text and errors
    /// otherwise so a test never silently types the wrong characters.
    static func insert(
        _ text: String,
        method: TextInputMethod,
        driver: SimDriver,
        udid: String
    ) throws {
        switch method {
        case .keyboard:
            guard TextToHIDEvents.validateText(text) else {
                throw TextInputError(description:
                    "input-method 'keyboard' cannot type text containing non-US-keyboard "
                    + "characters (accented letters, non-Latin scripts, emoji); use the default paste method.")
            }
            for event in try TextToHIDEvents.convertTextToHIDEvents(text) {
                try driver.key(usage: event.usage, down: event.down, udid: udid)
                // Pace events: sent back-to-back the guest keyboard coalesces and
                // drops trailing characters. A short gap lets each keystroke register.
                usleep(12 * 1000)
            }
        case .paste:
            // The paste target is the first responder, so the field must already
            // be focused. Save and restore the user's prior pasteboard best-effort.
            let saved = try? SimShell.pbpaste(udid: udid)
            try SimShell.pbcopy(text, udid: udid)
            for event in KeyInput.pasteCombo() {
                try driver.key(usage: event.usage, down: event.down, udid: udid)
            }
            if let saved { try? SimShell.pbcopy(saved, udid: udid) }
        }
    }
}
