// MultiTouchCrown.swift
//
// Two specialized input capabilities on the `sipi` CLI:
//
//   multitouch  Two-finger touch phase at two points (e.g. pinch-to-zoom) via
//               SPSimBridge.multiTouchUDID. `phase` 1 = begin/move, 2 = end.
//               Coordinates follow the sipi --norm (default) / --pixel
//               convention like tap/swipe/touch.
//
//   crown       Send a Digital Crown rotation delta (Apple Watch simulators
//               only) via SPSimBridge.sendDigitalCrownDelta.

import ArgumentParser
import Foundation
import SimCore
import SimNative

// MARK: - multitouch

extension Sipi {
    struct MultiTouch: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "multitouch",
            abstract: "Two-finger touch phase at two points (e.g. pinch). Coordinates are --norm (default) or --pixel."
        )

        @OptionGroup var coordinate: CoordinateUnitOptions

        @Argument(help: "Simulator UDID.")
        var udid: String

        @Argument(help: "Touch phase: 1 = begin/move, 2 = end.")
        var phase: Int

        @Argument(help: "First-finger X (normalized 0...1, or pixels with --pixel).")
        var x1: Double

        @Argument(help: "First-finger Y (normalized 0...1, or pixels with --pixel).")
        var y1: Double

        @Argument(help: "Second-finger X (normalized 0...1, or pixels with --pixel).")
        var x2: Double

        @Argument(help: "Second-finger Y (normalized 0...1, or pixels with --pixel).")
        var y2: Double

        func validate() throws {
            try coordinate.validate()
            guard let _ = TouchPhase(rawValue: phase) else {
                throw ValidationError("Phase must be 1 (begin/move) or 2 (end).")
            }
        }

        func run() throws {
            guard let touchPhase = TouchPhase(rawValue: phase) else {
                throw ValidationError("Phase must be 1 (begin/move) or 2 (end).")
            }
            let driver = NativeDriver()
            let a = try normalizedPoint(x: x1, y: y1, unit: coordinate.unit, udid: udid)
            let b = try normalizedPoint(x: x2, y: y2, unit: coordinate.unit, udid: udid)
            try driver.multiTouch(a, b, phase: touchPhase, udid: udid)
            print("ok")
        }
    }
}

// MARK: - crown

extension Sipi {
    struct Crown: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "crown",
            abstract: "Send a Digital Crown rotation delta (Apple Watch simulators only)."
        )

        @Argument(help: "Simulator UDID.")
        var udid: String

        @Argument(help: "Crown rotation delta (positive scrolls one way, negative the other).")
        var delta: Double

        func run() throws {
            let driver = NativeDriver()
            try driver.crown(delta: delta, udid: udid)
            print("ok")
        }
    }
}
