// SliderPlan.swift
//
// Adapted for SimPilot from AXe (https://github.com/cameroncooke/AXe),
// origin: Sources/AXe/Commands/Slider.swift — MIT License
// (Copyright (c) 2025 Cameron Cooke; see THIRD_PARTY_LICENSES.md). The slider
// track GEOMETRY is lifted verbatim; the TIMING + TOLERANCE constants are
// re-tuned for native Indigo HID (see notes below).
//
// Slider set-to-value planning and verification math. `sipi slider --value
// <0...100>` resolves a slider element, drags its thumb to the target, and polls
// AXValue to verify.
//
// Two kinds of constants live here, and they are NOT treated the same way:
//
//   1. GEOMETRY (range coordinate offsets, the wide-range start back-off, the
//      end-X clamp). These describe where on the track the thumb sits for a given
//      normalized value and are a property of UIKit/SwiftUI slider rendering, not
//      of the HID transport. They are lifted verbatim from AXe.
//
//   2. TIMING + TOLERANCE (drag steps, duration, initial/final holds, the
//      accepted value delta). AXe's values (120 steps / 2.4s / tolerance 0.0007)
//      were tuned against FBSimulatorControl's HID timing. SimNative injects
//      through the Indigo phase primitive on a different clock, so these are
//      RE-TUNED for native timing here and the accepted tolerance is DEFINED
//      explicitly (see `valueTolerance`).
//
// Pure Foundation: no SimBridge, no private frameworks. The plan is computed from
// an AXNode (the matched slider) and the application frame; the driver/CLI feeds
// the resulting logical drag to the HID layer and re-reads AXValue to verify.

import Foundation

public enum SliderPlan {

    // MARK: - Geometry (verbatim from AXe; describes slider rendering)

    /// Coordinate offset applied when dragging the thumb toward a LOWER value.
    static let lowRangeCoordinateOffset = 0.0268
    /// Coordinate offset applied when dragging the thumb toward a HIGHER value.
    static let highRangeCoordinateOffset = 0.0271

    // MARK: - Timing + tolerance (RE-TUNED for native Indigo HID)

    /// Number of interpolated touch-move steps for the slider drag. AXe used 120
    /// for FB timing; native Indigo injection is per-event slower, so a coarser
    /// but still smooth 80-step ramp is used to keep the drag near the same wall
    /// time without over-saturating the transport.
    public static let dragSteps = 80
    /// Total drag duration (seconds). Re-tuned from AXe's 2.4s.
    public static let dragDuration: TimeInterval = 2.0
    /// Hold after touch-down before moving (lets the recognizer latch the thumb).
    public static let dragInitialHold: TimeInterval = 0.05
    /// Hold before touch-up (lets the final value settle before release).
    public static let dragFinalHold: TimeInterval = 0.2

    /// Verification: maximum seconds to poll AXValue after the drag.
    public static let verificationTimeout: TimeInterval = 1.5
    /// Verification: seconds between AXValue polls.
    public static let verificationPollInterval: TimeInterval = 0.1
    /// Verification: settle delay after first seeing an in-tolerance value, then
    /// re-read once to confirm it is stable.
    public static let verificationStabilityDelay: TimeInterval = 0.3

    /// DEFAULT accepted value tolerance (normalized 0...1). The observed AXValue
    /// is considered to have reached the target when it is within this delta.
    ///
    /// AXe's 0.0007 was tuned for FB HID timing; native Indigo injection lands
    /// the thumb slightly less precisely, so the native default is 0.02 (2% of
    /// the full 0...100 range, i.e. +-2 on the percentage scale). This is the
    /// documented Gate 3 / §6.11 numeric tolerance and is overridable per call.
    public static let valueTolerance = 0.02

    // MARK: - Errors

    public enum SliderError: Error, CustomStringConvertible, Equatable {
        case notASlider(typeDescription: String)
        case invalidFrame(reason: String)
        case nonNumericValue(raw: String?)
        case valueOutOfRange(raw: String)
        case notReached(target: Double, observed: String?)

        public var description: String {
            switch self {
            case .notASlider(let typeDescription):
                return "Matched element is not a slider (type: \(typeDescription)). Use --element-type Slider or a more specific --id/--label selector."
            case .invalidFrame(let reason):
                return reason
            case .nonNumericValue(let raw):
                return "Matched slider does not expose a numeric AXValue (got \(raw.map { "'\($0)'" } ?? "none")), so it cannot be set deterministically."
            case .valueOutOfRange(let raw):
                return "Matched slider AXValue is outside the supported 0...100 range: \(raw)."
            case .notReached(let target, let observed):
                return "Slider value did not reach \(SliderPlan.formatPercent(target * 100)) after the drag. Observed AXValue: \(observed ?? "none")."
            }
        }
    }

    // MARK: - Plan

    /// A planned slider drag in the simulator's logical coordinate space.
    public struct DragPlan: Equatable, Sendable {
        public let logicalStart: Point
        public let logicalEnd: Point
        public let currentNormalized: Double
        public let targetNormalized: Double
        public let commandedNormalized: Double
        /// True when the slider is already within tolerance of the target (no
        /// drag needed).
        public let alreadyAtTarget: Bool
    }

    /// Build a drag plan to move `element` (a slider) to `targetNormalized`
    /// (0...1). `applicationFrame` clamps the drag end so the finger stays on
    /// screen. The geometry is AXe's verbatim track math.
    public static func makeDragPlan(
        element: AXNode,
        applicationFrame: AXNode.Frame?,
        targetNormalized: Double,
        tolerance: Double = valueTolerance
    ) throws -> DragPlan {
        guard element.isSliderLikeControl else {
            let typeDescription = element.type ?? element.role ?? "unknown"
            throw SliderError.notASlider(typeDescription: typeDescription)
        }
        guard let frame = element.frame else {
            throw SliderError.invalidFrame(reason: "Matched slider has no frame.")
        }
        guard frame.width > 0, frame.height > 0 else {
            throw SliderError.invalidFrame(reason: "Matched slider has an invalid frame size (\(frame.width)x\(frame.height)).")
        }

        let currentNormalized = try parseNormalizedAXValue(element.normalizedValue)
        let centerY = frame.y + (frame.height / 2.0)
        let commandedNormalized = commandedNormalizedValue(
            currentNormalized: currentNormalized,
            targetNormalized: targetNormalized,
            tolerance: tolerance
        )
        let nominalStartX = frame.x + (frame.width * currentNormalized)
        let startX = dragStartX(
            frame: frame,
            nominalStartX: nominalStartX,
            currentNormalized: currentNormalized,
            targetNormalized: targetNormalized,
            tolerance: tolerance
        )
        let fingerOffsetFromNominalStart = startX - nominalStartX
        let rawEndX = frame.x + (frame.width * commandedNormalized) + fingerOffsetFromNominalStart
        let endX = clampedDragEndX(rawEndX, applicationFrame: applicationFrame)

        return DragPlan(
            logicalStart: Point(x: startX, y: centerY),
            logicalEnd: Point(x: endX, y: centerY),
            currentNormalized: currentNormalized,
            targetNormalized: targetNormalized,
            commandedNormalized: commandedNormalized,
            alreadyAtTarget: abs(currentNormalized - targetNormalized) <= tolerance
        )
    }

    /// Whether an observed normalized value has reached the target.
    public static func isWithinTolerance(
        observed: Double,
        target: Double,
        tolerance: Double = valueTolerance
    ) -> Bool {
        abs(observed - target) <= tolerance
    }

    // MARK: - Geometry helpers (verbatim from AXe)

    static func dragStartX(
        frame: AXNode.Frame,
        nominalStartX: Double,
        currentNormalized: Double,
        targetNormalized: Double,
        tolerance: Double
    ) -> Double {
        guard currentNormalized >= 1.0 - tolerance, targetNormalized < currentNormalized else {
            return nominalStartX
        }
        return nominalStartX - (frame.height / 2.0)
    }

    static func commandedNormalizedValue(
        currentNormalized: Double,
        targetNormalized: Double,
        tolerance: Double
    ) -> Double {
        if abs(currentNormalized - targetNormalized) <= tolerance {
            return currentNormalized
        }
        if targetNormalized < currentNormalized {
            return targetNormalized - lowRangeCoordinateOffset
        }
        return targetNormalized + highRangeCoordinateOffset
    }

    static func clampedDragEndX(
        _ x: Double,
        applicationFrame: AXNode.Frame?
    ) -> Double {
        guard let applicationFrame, applicationFrame.width > 0 else {
            return x
        }
        return min(max(x, applicationFrame.x), applicationFrame.x + applicationFrame.width)
    }

    /// Parse an AXValue into a normalized 0...1 value. Accepts a bare fraction
    /// (0...1), a percentage suffix ("50%"), or an integer/decimal > 1 treated as
    /// a percentage. Verbatim from AXe's parseNormalizedAXValue.
    public static func parseNormalizedAXValue(_ rawValue: String?) throws -> Double {
        guard let rawValue else {
            throw SliderError.nonNumericValue(raw: nil)
        }
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            throw SliderError.nonNumericValue(raw: rawValue)
        }

        let isPercent = trimmedValue.hasSuffix("%")
        let numericText = trimmedValue.replacingOccurrences(of: "%", with: "")
        guard let parsedValue = Double(numericText.trimmingCharacters(in: .whitespacesAndNewlines)),
              parsedValue.isFinite else {
            throw SliderError.nonNumericValue(raw: rawValue)
        }

        let normalizedValue = isPercent || parsedValue > 1.0 ? parsedValue / 100.0 : parsedValue
        guard (0...1).contains(normalizedValue) else {
            throw SliderError.valueOutOfRange(raw: rawValue)
        }
        return normalizedValue
    }

    // MARK: - Formatting

    public static func formatPercent(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }

    public static func formatNormalized(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}
