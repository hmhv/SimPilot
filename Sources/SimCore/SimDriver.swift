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
    /// SET the device orientation: native PurpleEvent SET first, osascript menu
    /// fallback (which also covers face-up / face-down).
    func setOrientation(_ name: OrientationSetName, udid: String) throws
    /// Two-finger touch phase at two normalized 0...1 points (pinch / multitouch).
    /// `phase` 1 = begin/move, 2 = end.
    func multiTouch(_ a: Point, _ b: Point, phase: TouchPhase, udid: String) throws
    /// Send a Digital Crown rotation delta (Apple Watch simulators only).
    func crown(delta: Double, udid: String) throws
}
