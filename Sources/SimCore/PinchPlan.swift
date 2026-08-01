// PinchPlan.swift
//
// Pure geometry for a two-finger pinch, built on the `multiTouch` primitive the
// way `Gesture` is built on `swipe`. The driver can already deliver a two-finger
// phase at two points; what was missing was the interpolation that turns that
// into a real pinch, so every caller had to hand-assemble phases.
//
// The two contact points travel along the VERTICAL axis through the center.
// Normalized 0...1 coordinates are not square — a diagonal spread would trace
// different physical distances on an iPhone and an iPad, so a single axis keeps
// the gesture shape predictable across devices. Vertical is chosen over
// horizontal because it stays inside the safe area on the wide, short layouts
// (landscape phones) where a horizontal spread would run into the screen edges.
//
// Pure Foundation: no SimBridge, no private frameworks, fully unit-testable.

import Foundation

/// Which way the fingers travel.
public enum PinchDirection: String, Sendable, CaseIterable {
    /// Fingers move together — the zoom-out gesture.
    case pinchIn = "in"
    /// Fingers move apart — the zoom-in gesture.
    case pinchOut = "out"

    public var summary: String {
        switch self {
        case .pinchIn: return "Fingers move together (zoom out)"
        case .pinchOut: return "Fingers move apart (zoom in)"
        }
    }
}

public struct PinchPlanError: Error, CustomStringConvertible, Equatable {
    public let description: String
}

/// One two-finger sample: where each contact sits and which phase to send.
///
/// Lives outside `PinchPlan` because the driver consumes it for any interpolated
/// two-finger gesture, not only pinches.
public struct MultiTouchFrame: Equatable, Sendable {
    public let a: Point
    public let b: Point
    public let phase: TouchPhase

    public init(a: Point, b: Point, phase: TouchPhase) {
        self.a = a
        self.b = b
        self.phase = phase
    }
}

/// An interpolated two-finger pinch as an ordered list of touch frames.
public struct PinchPlan: Equatable, Sendable {
    public typealias Frame = MultiTouchFrame

    public let frames: [Frame]

    /// Normalized gap the fingers converge to (pinch-in) or start from
    /// (pinch-out). Not zero: two contacts at the same coordinate read as one
    /// finger, and the gesture recognizer would see a tap instead of a pinch.
    public static let minimumSeparation = 0.05

    /// Default end separation for pinch-out / start separation for pinch-in.
    public static let defaultSeparation = 0.4

    /// Default number of interpolated move frames between the endpoints. Matches
    /// the density `drag` uses per unit of travel closely enough that UIKit's
    /// pinch recognizer sees a smooth, continuous scale change.
    public static let defaultSteps = 20

    /// Build the frame list for a pinch centered on `center`.
    ///
    /// - Parameters:
    ///   - center: normalized 0...1 midpoint between the two fingers.
    ///   - separation: the WIDE end of the gesture — where pinch-out finishes and
    ///     pinch-in starts. The narrow end is always `minimumSeparation`.
    ///   - direction: which way the fingers travel.
    ///   - steps: interpolated move frames between the endpoints.
    ///
    /// Both contacts are clamped into 0...1. Clamping shrinks the effective
    /// separation rather than sliding the center, because a pinch whose center
    /// drifts mid-gesture reads as a two-finger pan.
    public static func make(
        center: Point,
        separation: Double = defaultSeparation,
        direction: PinchDirection,
        steps: Int = defaultSteps
    ) throws -> PinchPlan {
        guard (0.0...1.0).contains(center.x), (0.0...1.0).contains(center.y) else {
            throw PinchPlanError(description: "pinch center must be normalized 0...1, got (\(center.x), \(center.y))")
        }
        guard separation > minimumSeparation, separation <= 1.0 else {
            throw PinchPlanError(description:
                "pinch separation must be greater than \(minimumSeparation) and at most 1.0, got \(separation)")
        }
        guard steps >= 1, steps <= 200 else {
            throw PinchPlanError(description: "pinch steps must be 1...200, got \(steps)")
        }

        // The largest half-gap that keeps both contacts on screen. A center near
        // an edge simply yields a shorter pinch instead of an off-screen touch.
        let headroom = min(center.y, 1.0 - center.y)
        let wideHalf = min(separation / 2.0, headroom)
        let narrowHalf = min(minimumSeparation / 2.0, wideHalf)

        guard wideHalf > narrowHalf else {
            throw PinchPlanError(description:
                """
                pinch center (\(center.x), \(center.y)) leaves no room to travel: \
                the fingers would need at least \(minimumSeparation) of vertical space. \
                Move the center toward the middle of the screen or reduce the separation.
                """)
        }

        let startHalf = direction == .pinchOut ? narrowHalf : wideHalf
        let endHalf = direction == .pinchOut ? wideHalf : narrowHalf

        func frame(halfGap: Double, phase: TouchPhase) -> Frame {
            Frame(
                a: Point(x: center.x, y: center.y - halfGap),
                b: Point(x: center.x, y: center.y + halfGap),
                phase: phase
            )
        }

        var frames: [Frame] = [frame(halfGap: startHalf, phase: .begin)]
        // Interpolate the half-gap; `steps` counts the moves after the initial
        // touch-down, with the last one landing exactly on `endHalf`.
        for step in 1...steps {
            let progress = Double(step) / Double(steps)
            let halfGap = startHalf + (endHalf - startHalf) * progress
            frames.append(frame(halfGap: halfGap, phase: .begin))
        }
        // Lift both fingers from the final separation.
        frames.append(frame(halfGap: endHalf, phase: .end))
        return PinchPlan(frames: frames)
    }

    /// Per-frame delay for a pinch that should take `duration` seconds overall.
    /// The begin frame is instantaneous, so the budget is spread over the moves.
    public static func frameDelay(duration: TimeInterval, steps: Int) -> TimeInterval {
        guard steps > 0, duration > 0 else { return 0 }
        return duration / Double(steps)
    }
}
