// KeyInput.swift
//
// Composes higher-level keyboard inputs (key, key-sequence, key-combo) onto the
// raw `HIDKeyEvent` (USB HID usage + down/up) the driver layer injects. Mirrors
// AXe's Key / KeySequence / KeyCombo command semantics:
//   * key          — one down + up (optionally held for a duration).
//   * key-sequence — each key pressed and released in order.
//   * key-combo    — hold modifiers (in order), press+release the target key,
//                    then release modifiers in reverse (LIFO) order.
//
// AXe builds these as `FBSimulatorHIDEvent` trees; SimCore is FB-free, so the
// same ordering is produced as a flat `[HIDKeyEvent]` the driver feeds to the
// native HID injector one event at a time. Inter-key / hold delays are not
// encoded here (they are timing, applied by the driver/CLI), so this stays a
// pure, unit-testable ordering function.
//
// Pure Foundation: no SimBridge, no private frameworks.

import Foundation

public enum KeyInput {
    /// USB HID usage code for Left Command (GUI). Used by the non-US `type`
    /// paste path (Cmd+V).
    public static let leftCommandUsage = 227
    /// USB HID usage code for the V key (paste target with Cmd held).
    public static let vUsage = 25

    /// One key press: down then up.
    public static func keyPress(usage: Int) -> [HIDKeyEvent] {
        [
            HIDKeyEvent(usage: usage, down: true),
            HIDKeyEvent(usage: usage, down: false)
        ]
    }

    /// A sequence of keys, each pressed and released in order. The CLI inserts an
    /// inter-key delay between presses (timing, not ordering).
    public static func keySequence(usages: [Int]) -> [HIDKeyEvent] {
        usages.flatMap { keyPress(usage: $0) }
    }

    /// Hold `modifiers` (in the given order), press+release `key`, then release
    /// the modifiers in reverse (LIFO) order — exactly AXe's KeyCombo ordering.
    public static func keyCombo(modifiers: [Int], key: Int) -> [HIDKeyEvent] {
        var events: [HIDKeyEvent] = []
        for modifier in modifiers {
            events.append(HIDKeyEvent(usage: modifier, down: true))
        }
        events.append(contentsOf: keyPress(usage: key))
        for modifier in modifiers.reversed() {
            events.append(HIDKeyEvent(usage: modifier, down: false))
        }
        return events
    }

    /// Cmd+V paste combo — used by the non-US `type` fallback after focus is
    /// established and text is on the simulator pasteboard.
    public static func pasteCombo() -> [HIDKeyEvent] {
        keyCombo(modifiers: [leftCommandUsage], key: vUsage)
    }
}
