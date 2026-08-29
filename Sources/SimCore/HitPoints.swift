// HitPoints.swift
//
// Turns raw accessibility frames into a point that can actually be touched.
//
// A frame is not a tap target. `describe-ui` lists every element the app
// exposes, including ones scrolled far outside the display, and an element's
// frame can extend past the screen on its own (a button taller than the
// display, a row half-way off the top). Touching the center of such a frame
// sends the touch to a coordinate the screen does not have, which the injector
// accepts and the app never sees — the tap "succeeds" and nothing happens.
//
// Every node therefore carries `hitPoint` (a point that is on the screen) and
// `onscreen` (whether the element can be touched at all right now). The bridge
// fills `hitPoint` in for elements it discovered by hit-testing, because for
// those the probe point is ground truth even when the reported frame is in some
// other coordinate space — that is the case for cross-process remote views such
// as the share sheet, whose frames are local to the remote view. Everything
// else is filled in here from the frame clipped to the screen.

import Foundation

public enum HitPoints {
    /// Fill in `hitPoint`/`onscreen` for every node in `roots`, using `screen`
    /// as the visible area. Nodes that already carry a hit-test-derived
    /// `hitPoint` keep it — a measured screen point beats anything computed
    /// from a frame that may not be in screen space.
    public static func annotate(_ roots: [AXNode], screen: AXNode.Frame?) -> [AXNode] {
        guard let screen, screen.width > 0, screen.height > 0 else { return roots }
        return roots.map { annotate($0, screen: screen) }
    }

    /// The screen frame to clip against: the root Application node's frame, or
    /// the first root's frame when no Application node is present.
    public static func screenFrame(of roots: [AXNode]) -> AXNode.Frame? {
        let frame = (roots.first { $0.type == "Application" } ?? roots.first)?.frame
        guard let frame, frame.width > 0, frame.height > 0 else { return nil }
        return frame
    }

    private static func annotate(_ node: AXNode, screen: AXNode.Frame) -> AXNode {
        var copy = node
        if let children = node.children {
            copy.children = children.map { annotate($0, screen: screen) }
        }

        // A probe-derived hit point is measured, not derived: keep it, and take
        // it as proof the element is reachable on screen.
        if let measured = node.hitPoint {
            copy.onscreen = node.onscreen ?? screen.contains(measured)
            return copy
        }

        guard let frame = node.frame, frame.width > 0, frame.height > 0 else {
            copy.onscreen = false
            return copy
        }

        guard let visible = frame.intersected(with: screen) else {
            // Entirely outside the display: it exists, it just cannot be
            // touched until something scrolls it into view. Deliberately no
            // hitPoint — there is no honest point to offer.
            copy.onscreen = false
            return copy
        }

        copy.onscreen = true
        copy.hitPoint = AXNode.Frame.Point(
            x: visible.x + (visible.width / 2.0),
            y: visible.y + (visible.height / 2.0)
        )
        return copy
    }
}

extension AXNode.Frame {
    /// Whether `point` lies inside this frame.
    public func contains(_ point: AXNode.Frame.Point) -> Bool {
        point.x >= x && point.x < x + width && point.y >= y && point.y < y + height
    }
}
