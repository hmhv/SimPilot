// SimDriver.swift
//
// Framework-agnostic seam between the CLI/composition layer and a concrete
// backend. SimNative is the only implementation today (private frameworks via
// SimBridge); a future backend could be added behind this same protocol without
// a second build.

import Foundation

/// Errors surfaced by a SimDriver. Drivers must turn private-framework failures
/// and not-yet-implemented seams into actionable, typed errors rather than
/// crashing.
public enum SimDriverError: Error, CustomStringConvertible {
    /// A driver method exists on the protocol but is filled in by a later stage.
    case notImplemented(String)
    /// The underlying bridge/framework reported a failure.
    case bridge(String)

    public var description: String {
        switch self {
        case .notImplemented(let what):
            return "\(what): not yet implemented"
        case .bridge(let message):
            return message
        }
    }
}

/// The low-level capabilities every backend must provide. Higher-level features
/// (label/id resolution, `type`, key-combo, slider, gesture presets, polling)
/// are composed on top of this protocol inside SimCore.
public protocol SimDriver {
    func devices() throws -> [Device]
    /// Frontmost (+ System UI) accessibility tree. `deep == true` runs the grid
    /// pass; the default fast path is frontmost+recursive.
    func describe(_ udid: String, deep: Bool) throws -> [AXNode]
    /// Single `objectAtPoint` lookup — cheap, no grid pass.
    func element(at point: Point, udid: String) throws -> AXNode?
    /// Write text straight into the element at `point` (LOGICAL coordinates, the
    /// `describe`/`element(at:)` space) through the accessibility bridge. Needs no
    /// keyboard, no pasteboard, and no focus, so it is the text-entry path that
    /// survives a guest keyboard layout / IME — and the only one that works at all
    /// on runtimes where keyboard HID is not delivered.
    ///
    /// Returning without throwing means the setter RAN, not that the app took the
    /// value: an element that ignores the write accepts the call all the same.
    /// Callers that need certainty must re-read the value from a fresh process.
    /// Throws when there is no element at the point or it takes no value write.
    func setValue(_ value: String, at point: Point, udid: String) throws
    /// Tap at a normalized 0...1 point.
    func tap(_ point: Point, udid: String) throws
    /// Send one touch phase at a normalized 0...1 point.
    func touch(_ point: Point, phase: TouchPhase, udid: String) throws
    /// Swipe from `a` to `b` over `duration`.
    func swipe(_ a: Point, _ b: Point, duration: TimeInterval, udid: String) throws
    /// Send a keyboard event by USB HID usage code.
    func key(usage: Int, down: Bool, udid: String) throws
    /// Press a hardware button.
    func button(_ button: HardwareButton, udid: String) throws
    /// Capture a single framebuffer frame to a PNG file.
    func screenshot(to url: URL, udid: String) throws
    /// Native READ of the current physical UI orientation.
    func uiOrientation(_ udid: String) throws -> UIOrientation
    /// SET the device orientation: native PurpleEvent SET first, then devicectl
    /// (the only headless path to face-up / face-down), then the osascript menu
    /// on toolchains that still ship Simulator.app.
    func setOrientation(_ name: OrientationSetName, udid: String) throws
    /// Two-finger touch phase at two normalized 0...1 points (pinch / multitouch).
    /// `phase` 1 = begin/move, 2 = end.
    func multiTouch(_ a: Point, _ b: Point, phase: TouchPhase, udid: String) throws
    /// Send a whole interpolated two-finger gesture.
    ///
    /// Worth implementing rather than leaving to the default below: an
    /// implementation that knows the device can resolve the orientation and
    /// logical extent ONCE for the gesture, the way `swipe` and the composite
    /// drag do. Going through `multiTouch` per frame re-resolves both per
    /// endpoint, which on a rotated device means two CoreSimulator round trips
    /// plus two accessibility-tree fetches per frame — for a default 22-frame
    /// pinch that is 44 of each, mid-gesture, and the guest stops recognizing it
    /// as a pinch.
    ///
    /// `frameDelay` paces the interpolated moves; the opening and closing frames
    /// are sent without an added gap.
    ///
    /// Has a default implementation, so conforming types written before it
    /// existed keep compiling.
    func multiTouchSequence(_ frames: [MultiTouchFrame], frameDelay: TimeInterval, udid: String) throws
    /// Send a Digital Crown rotation delta (Apple Watch simulators only).
    func crown(delta: Double, udid: String) throws
}

extension SimDriver {
    /// Frame-by-frame fallback over `multiTouch`.
    ///
    /// Correct but slower than a native implementation: each frame re-resolves
    /// whatever per-call state `multiTouch` needs. Adopters that can hoist that
    /// work out of the loop should override this — see the protocol requirement.
    public func multiTouchSequence(
        _ frames: [MultiTouchFrame],
        frameDelay: TimeInterval,
        udid: String
    ) throws {
        guard !frames.isEmpty else { return }
        let lastIndex = frames.count - 1
        for (index, frame) in frames.enumerated() {
            try multiTouch(frame.a, frame.b, phase: frame.phase, udid: udid)
            // Pace the interpolated moves only; the opening touch-down and the
            // closing lift follow immediately so the recognizer never sees a
            // stalled hold at either end.
            if index > 0, index < lastIndex, frameDelay > 0 {
                usleep(useconds_t(min(max(frameDelay, 0), 5) * 1_000_000))
            }
        }
    }
}
