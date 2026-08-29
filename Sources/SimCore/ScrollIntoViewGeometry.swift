// ScrollIntoViewGeometry.swift
//
// The pure geometry behind bringing an off-screen element into view: which way
// the content has to move, and the swipe that moves it. Kept out of the driver
// so it can be tested without a simulator; the driver in the `sipi` target
// supplies the gestures and the re-reads.

import Foundation

public enum ScrollIntoViewGeometry {
    /// Which way the content has to move for the element to become visible.
    public enum Direction: Equatable, Sendable {
        case contentBelow   // element is past the bottom edge: swipe up
        case contentAbove   // element is past the top edge: swipe down
        case contentRight   // element is past the trailing edge: swipe left
        case contentLeft    // element is past the leading edge: swipe right
    }

    /// Fraction of the screen one swipe travels.
    public static let travel = 0.45

    /// The direction `frame` lies in relative to `screen`, or nil when it
    /// already overlaps the screen and needs no scrolling.
    public static func direction(of frame: AXNode.Frame, screen: AXNode.Frame) -> Direction? {
        if frame.intersected(with: screen) != nil { return nil }
        if frame.y >= screen.y + screen.height { return .contentBelow }
        if frame.y + frame.height <= screen.y { return .contentAbove }
        if frame.x >= screen.x + screen.width { return .contentRight }
        if frame.x + frame.width <= screen.x { return .contentLeft }
        return nil
    }

    /// Normalized start/end of the swipe that moves content in `direction`.
    ///
    /// The gesture is placed on the target's own axis wherever that is known: a
    /// vertical scroll drags down the column the element sits in, a horizontal
    /// one along its row. Dragging the middle of the screen instead is what
    /// makes a scroll hit the wrong thing — a sheet, a pager, a side-by-side
    /// pane — and a swipe that lands on the wrong view is not undone by the
    /// action failing afterwards.
    ///
    /// Kept away from the very edges so the gesture is not taken as a system
    /// edge swipe (back navigation, Control Center).
    public static func swipePoints(
        for direction: Direction,
        target: AXNode.Frame? = nil,
        screen: AXNode.Frame? = nil
    ) -> (from: Point, to: Point) {
        let near = 0.5 - (travel / 2.0)
        let far = 0.5 + (travel / 2.0)

        // Where along the cross axis to drag, normalized, clamped away from the
        // edges. Falls back to the middle when the target gives no useful hint.
        func crossAxis(_ value: Double?, origin: Double?, extent: Double?) -> Double {
            guard let value, let origin, let extent, extent > 0 else { return 0.5 }
            return min(max((value - origin) / extent, edgeMargin), 1.0 - edgeMargin)
        }

        let x = crossAxis(target.map { $0.x + $0.width / 2.0 },
                          origin: screen?.x, extent: screen?.width)
        let y = crossAxis(target.map { $0.y + $0.height / 2.0 },
                          origin: screen?.y, extent: screen?.height)

        switch direction {
        case .contentBelow:
            return (Point(x: x, y: far), Point(x: x, y: near))
        case .contentAbove:
            return (Point(x: x, y: near), Point(x: x, y: far))
        case .contentRight:
            return (Point(x: far, y: y), Point(x: near, y: y))
        case .contentLeft:
            return (Point(x: near, y: y), Point(x: far, y: y))
        }
    }

    /// How far from a screen edge a gesture must stay to avoid being read as a
    /// system edge swipe.
    private static let edgeMargin = 0.1
}
