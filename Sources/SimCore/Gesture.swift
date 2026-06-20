// Gesture.swift
//
// Adapted for SimPilot from AXe (https://github.com/cameroncooke/AXe),
// origin: Sources/AXe/Commands/Gesture.swift — MIT License
// (Copyright (c) 2025 Cameron Cooke; see THIRD_PARTY_LICENSES.md).
//
// Directional / scroll gesture presets over the swipe primitive. Mirrors AXe's
// `Gesture` command set: scroll-{up,down,left,right} and
// swipe-from-{left,right,top,bottom}-edge.
//
// AXe computes preset coordinates in logical points from a supplied screen size
// (default 390x844 iPhone 15) and an absolute scroll distance / edge margin.
// SimNative drives in normalized 0...1, so the same geometry is expressed as
// fractions of the screen here: the scroll distance (200pt of 844pt tall ~=
// 0.237) and edge margin (20pt of 390pt wide ~= 0.051) are converted to
// normalized spans so the gesture shape matches AXe without needing the device's
// physical size. Per-preset default durations are preserved verbatim from AXe.
//
// Pure Foundation: no SimBridge, no private frameworks.

import Foundation

/// One preset gesture, resolvable to a normalized start/end swipe.
public enum GesturePreset: String, Sendable, CaseIterable {
    case scrollUp = "scroll-up"
    case scrollDown = "scroll-down"
    case scrollLeft = "scroll-left"
    case scrollRight = "scroll-right"
    case swipeFromLeftEdge = "swipe-from-left-edge"
    case swipeFromRightEdge = "swipe-from-right-edge"
    case swipeFromTopEdge = "swipe-from-top-edge"
    case swipeFromBottomEdge = "swipe-from-bottom-edge"

    public var summary: String {
        switch self {
        case .scrollUp: return "Scroll up in the center of the screen"
        case .scrollDown: return "Scroll down in the center of the screen"
        case .scrollLeft: return "Scroll left in the center of the screen"
        case .scrollRight: return "Scroll right in the center of the screen"
        case .swipeFromLeftEdge: return "Swipe from the left edge to center (back navigation)"
        case .swipeFromRightEdge: return "Swipe from the right edge to center (forward navigation)"
        case .swipeFromTopEdge: return "Swipe from the top edge downward"
        case .swipeFromBottomEdge: return "Swipe from the bottom edge upward"
        }
    }

    /// AXe's per-preset default duration (seconds). Scrolls are 0.5s; edge swipes
    /// are 0.3s.
    public var defaultDuration: TimeInterval {
        switch self {
        case .scrollUp, .scrollDown, .scrollLeft, .scrollRight:
            return 0.5
        case .swipeFromLeftEdge, .swipeFromRightEdge, .swipeFromTopEdge, .swipeFromBottomEdge:
            return 0.3
        }
    }

    /// Normalized 0...1 start/end points for this preset.
    ///
    /// Derived from AXe's logical-point geometry on its default 390x844 frame so
    /// the gesture shape matches: a 200pt scroll span over 844pt tall is a 0.237
    /// normalized span (half on each side of center); a 20pt edge margin over the
    /// matching axis is a ~0.051 normalized inset.
    public func normalizedEndpoints() -> (start: Point, end: Point) {
        let centerX = 0.5
        let centerY = 0.5
        // 200pt / 844pt (the AXe default tall axis) ~= 0.2370 total scroll span.
        let scrollHalfSpan = (200.0 / 844.0) / 2.0
        // 20pt edge margin over the AXe default 390x844 frame.
        let edgeMarginX = 20.0 / 390.0
        let edgeMarginY = 20.0 / 844.0

        switch self {
        case .scrollUp:
            // Content moves up: finger goes from below center to above center.
            return (Point(x: centerX, y: centerY + scrollHalfSpan),
                    Point(x: centerX, y: centerY - scrollHalfSpan))
        case .scrollDown:
            return (Point(x: centerX, y: centerY - scrollHalfSpan),
                    Point(x: centerX, y: centerY + scrollHalfSpan))
        case .scrollLeft:
            return (Point(x: centerX + scrollHalfSpan, y: centerY),
                    Point(x: centerX - scrollHalfSpan, y: centerY))
        case .scrollRight:
            return (Point(x: centerX - scrollHalfSpan, y: centerY),
                    Point(x: centerX + scrollHalfSpan, y: centerY))
        case .swipeFromLeftEdge:
            return (Point(x: edgeMarginX, y: centerY),
                    Point(x: 1.0 - edgeMarginX, y: centerY))
        case .swipeFromRightEdge:
            return (Point(x: 1.0 - edgeMarginX, y: centerY),
                    Point(x: edgeMarginX, y: centerY))
        case .swipeFromTopEdge:
            return (Point(x: centerX, y: edgeMarginY),
                    Point(x: centerX, y: 1.0 - edgeMarginY))
        case .swipeFromBottomEdge:
            return (Point(x: centerX, y: 1.0 - edgeMarginY),
                    Point(x: centerX, y: edgeMarginY))
        }
    }
}
