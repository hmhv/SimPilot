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

// MARK: - pinch

extension Sipi {
    struct Pinch: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "pinch",
            abstract: "Two-finger pinch (zoom) around a center point. Coordinates are --norm (default) or --pixel.",
            discussion: """
            Interpolates the two contacts along the vertical axis through the center:
            `out` spreads them apart (zoom in), `in` brings them together (zoom out).
            This is the composed form of `sipi multitouch`, which sends one raw phase
            at a time and leaves the interpolation to the caller.

            --separation is the WIDE end of the gesture in normalized units; the narrow
            end is fixed at 0.05 so the two contacts never collapse into one. A center
            close to the top or bottom edge shortens the travel instead of pushing a
            contact off screen.
            """
        )

        @OptionGroup var coordinate: CoordinateUnitOptions

        @Argument(help: "Simulator UDID.")
        var udid: String

        @Argument(help: "Direction: in (zoom out) or out (zoom in).")
        var direction: String

        @Option(name: .customLong("center-x"), help: "Center X (normalized 0...1, or pixels with --pixel). Default: screen center.")
        var centerX: Double?

        @Option(name: .customLong("center-y"), help: "Center Y (normalized 0...1, or pixels with --pixel). Default: screen center.")
        var centerY: Double?

        @Option(name: .long, help: "Widest normalized finger separation (default \(PinchPlan.defaultSeparation)).")
        var separation: Double = PinchPlan.defaultSeparation

        @Option(name: .long, help: "Total gesture duration in seconds (default 0.5).")
        var duration: Double = 0.5

        @Option(name: .long, help: "Interpolated move frames (default \(PinchPlan.defaultSteps), max 200).")
        var steps: Int = PinchPlan.defaultSteps

        func validate() throws {
            try coordinate.validate()
            guard PinchDirection(rawValue: direction) != nil else {
                throw ValidationError(
                    "Unknown pinch direction '\(direction)'. Valid: "
                    + PinchDirection.allCases.map(\.rawValue).joined(separator: ", ") + ".")
            }
            guard duration > 0, duration <= 30 else {
                throw ValidationError("Duration must be greater than 0 and at most 30 seconds.")
            }
            // Both center coordinates travel together: half a center is ambiguous.
            if (centerX == nil) != (centerY == nil) {
                throw ValidationError("Pass both --center-x and --center-y, or neither.")
            }
        }

        func run() throws {
            guard let pinchDirection = PinchDirection(rawValue: direction) else {
                throw ValidationError("Unknown pinch direction '\(direction)'.")
            }
            let driver = NativeDriver()
            let center: Point
            if let centerX, let centerY {
                center = try normalizedPoint(x: centerX, y: centerY, unit: coordinate.unit, udid: udid)
            } else {
                center = Point(x: 0.5, y: 0.5)
            }

            let plan: PinchPlan
            do {
                plan = try PinchPlan.make(
                    center: center,
                    separation: separation,
                    direction: pinchDirection,
                    steps: steps
                )
            } catch let error as PinchPlanError {
                throw ValidationError(error.description)
            }

            // One driver call for the whole gesture: it resolves the orientation
            // and logical extent once instead of per frame, which is what keeps a
            // rotated pinch fast enough for the guest to recognize.
            try driver.multiTouchSequence(
                plan.frames,
                frameDelay: PinchPlan.frameDelay(duration: duration, steps: steps),
                udid: udid
            )
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
