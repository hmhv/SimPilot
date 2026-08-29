// ScrollIntoView.swift
//
// Brings an off-screen element into view before it is touched.
//
// `describe-ui` lists every element the app exposes, including the ones that
// have scrolled out of the display. Their frames are still reported in content
// coordinates, so a row 800pt below the fold has a perfectly reasonable-looking
// frame whose center is nowhere on the screen. Sending a touch there is not an
// error anywhere in the stack — the injector accepts the coordinate and the
// guest simply has nothing at it — so the action reports success and does
// nothing. That is the worst possible outcome for a test harness: a green step
// that never happened.
//
// So an off-screen target is scrolled toward until it is reachable, and if it
// cannot be brought on screen the action fails loudly instead.

import Foundation
import SimCore
import SimNative

enum ScrollIntoView {
    /// How many scroll gestures to spend before giving up. Eight full swipes
    /// cover a long list without letting a non-scrolling screen spin.
    static let maxAttempts = 8

    /// Seconds per swipe. Long enough that the scroll view tracks the drag
    /// rather than flinging, so the stop position stays predictable.
    private static let duration = 0.25
    /// Settle time after a swipe, for the scroll to land and the accessibility
    /// tree to catch up.
    private static let settle = 0.35
    /// Poll interval while waiting for a scroll to stop moving.
    private static let stillnessPoll = 0.12
    /// How long to wait for the scroll to come to rest before tapping anyway.
    private static let stillnessTimeout = 2.0
    /// Movement below this many points between two reads counts as stopped.
    private static let stillnessEpsilon = 1.0

    typealias Direction = ScrollIntoViewGeometry.Direction

    /// Why bringing the element into view failed, for the caller's message.
    enum Failure: Error {
        /// The element stayed off screen after `attempts` scrolls, and the last
        /// scroll moved it no closer — nothing here scrolls.
        case stuck(attempts: Int, frame: AXNode.Frame)
        /// Still off screen after spending every attempt.
        case exhausted(attempts: Int, frame: AXNode.Frame)

        var reason: String {
            switch self {
            case .stuck(let attempts, let frame):
                return "it never reached the screen — after \(attempts) scroll\(attempts == 1 ? "" : "s") its frame is still at (\(Int(frame.x)), \(Int(frame.y))) and has not moved. Either nothing on this screen scrolls that way, or the element reports a frame that is not in screen coordinates (elements inside a share sheet or other cross-process view do), in which case no amount of scrolling will help"
            case .exhausted(let attempts, let frame):
                return "it is off screen at y=\(Int(frame.y)) and \(attempts) scrolls did not bring it into view"
            }
        }
    }

    /// Scroll until `resolve` reports an on-screen element, and return that
    /// resolution. `resolve` re-reads the tree each time it is called, so the
    /// caller always gets coordinates for the position the element ended in.
    ///
    /// Returns immediately when the first resolution is already on screen, so
    /// the normal path costs nothing.
    static func bring(
        driver: SimDriver,
        udid: String,
        resolve: () throws -> (resolution: TapResolution, screen: AXNode.Frame?)
    ) throws -> TapResolution {
        var (resolution, screen) = try resolve()
        if resolution.isOnScreen { return resolution }

        guard let screen, let frame = resolution.frame else { return resolution }
        var lastFrame = frame
        var attempts = 0

        while attempts < maxAttempts {
            guard let direction = ScrollIntoViewGeometry.direction(of: lastFrame, screen: screen) else { break }
            let points = ScrollIntoViewGeometry.swipePoints(for: direction, target: lastFrame, screen: screen)
            try driver.swipe(points.from, points.to, duration: duration, udid: udid)
            usleep(useconds_t(settle * 1_000_000))
            attempts += 1

            let next = try resolve()
            resolution = next.resolution
            // A scroll view keeps decelerating after the finger lifts. Resolving
            // the instant it comes into view yields coordinates the element has
            // already left, and the tap lands on whatever slid into that spot —
            // so wait for it to stop before handing the point back.
            if resolution.isOnScreen {
                let settled = try awaitStill(resolution, resolve: resolve)
                // Deceleration can carry the element straight through the
                // viewport and out the far side. Only stop once it has come to
                // rest somewhere it can actually be touched.
                if settled.isOnScreen { return settled }
                resolution = settled
            }
            guard let nextFrame = resolution.frame else { return resolution }

            // No movement means this screen does not scroll that way. Stop now
            // rather than burning the remaining attempts on a fixed layout.
            if abs(nextFrame.y - lastFrame.y) < 1.0, abs(nextFrame.x - lastFrame.x) < 1.0 {
                throw Failure.stuck(attempts: attempts, frame: nextFrame)
            }
            lastFrame = nextFrame
        }

        throw Failure.exhausted(attempts: attempts, frame: lastFrame)
    }

    /// Re-resolve until the element's frame stops moving, then return that
    /// resolution. Gives up after `stillnessTimeout` and returns the latest
    /// reading — a slow-moving carousel is still better tapped than not tapped,
    /// and the caller's own verification will catch a genuine miss.
    private static func awaitStill(
        _ initial: TapResolution,
        resolve: () throws -> (resolution: TapResolution, screen: AXNode.Frame?)
    ) throws -> TapResolution {
        var previous = initial
        let deadline = Date().addingTimeInterval(stillnessTimeout)
        while Date() < deadline {
            usleep(useconds_t(stillnessPoll * 1_000_000))
            let current = try resolve().resolution
            guard let a = previous.frame, let b = current.frame else { return current }
            if abs(a.x - b.x) < stillnessEpsilon, abs(a.y - b.y) < stillnessEpsilon {
                return current
            }
            previous = current
        }
        return previous
    }
}
