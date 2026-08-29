// Models.swift
//
// Pure Foundation value types shared across the native simulator driver layer.
// No SimBridge import, no Process(), no private frameworks — this target stays
// unit-testable with a mock SimDriver and keeps a future backend possible
// behind the same protocol.

import Foundation

/// One simulator device discovered through the driver.
public struct Device: Codable, Equatable, Sendable {
    public var udid: String
    public var name: String
    /// CoreSimulator SimDeviceState raw value (3 == Booted).
    public var state: Int
    public var stateString: String
    public var booted: Bool
    public var runtime: String?
    /// Device type / model name (CoreSimulator deviceTypeName), e.g. "iPhone 16".
    public var model: String?

    public init(
        udid: String,
        name: String,
        state: Int,
        stateString: String,
        booted: Bool,
        runtime: String? = nil,
        model: String? = nil
    ) {
        self.udid = udid
        self.name = name
        self.state = state
        self.stateString = stateString
        self.booted = booted
        self.runtime = runtime
        self.model = model
    }
}

/// A point in the simulator's logical coordinate space, normalized 0...1 of the
/// screen. The driver layer works in normalized coordinates internally; the CLI
/// converts `--pixel`/`--norm` inputs into this representation (Gate 4).
public struct Point: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// A single touch phase. Sequence `begin` -> `move`... -> `end` to tap/swipe.
public enum TouchPhase: Int, Codable, Sendable {
    case begin = 1
    case end = 2
}

/// A hardware button the driver can press.
public enum HardwareButton: String, Codable, Sendable, CaseIterable {
    case home
    case lock
    case sideButton = "side_button"
    case appSwitcher = "app_switcher"
    case siri
    case swipeHome = "swipe_home"
}

/// Physical UI orientation as reported by the simulator screen
/// (SimulatorKit.SimDeviceScreen.uiOrientation, UInt32 1...4).
public enum UIOrientation: Int, Codable, Sendable {
    case portrait = 1
    case portraitUpsideDown = 2
    case landscapeLeft = 3
    case landscapeRight = 4
}

/// How to locate an element for an action like tap. The CLI composes higher
/// level commands (`tap --label/--id/--value`, `--point x,y`) onto this.
public enum AXSelector: Codable, Equatable, Sendable {
    case label(String)
    case identifier(String)
    case value(String)
    case point(Point)
}

/// One accessibility node. Mirrors the describe-ui JSON contract exactly: a node
/// may carry AXLabel, AXValue, role_description, role, type, subrole,
/// AXUniqueId, enabled, frame{x,y,width,height}, children. `role` is the raw
/// accessibility role (e.g. "AXButton"); `type` is the same value with a leading
/// "AX" stripped; `subrole` is emitted only when the element carries one (Gate 2
/// node-shape fidelity). Skills grep the pretty-printed output as raw text, so
/// the field names and nesting here are load-bearing.
public struct AXNode: Codable, Equatable, Sendable {
    public var AXLabel: String?
    public var AXValue: String?
    public var role_description: String?
    public var role: String?
    public var type: String?
    public var subrole: String?
    public var AXUniqueId: String?
    public var enabled: Bool?
    public var frame: Frame?
    /// The screen point to touch to reach this element, in the same logical
    /// coordinate space as `frame`.
    ///
    /// `frame` alone is not a safe tap target. It is the element's own frame in
    /// whatever space the element reports, which is NOT always the screen: it
    /// can extend past the screen (a row scrolled out of view, an element taller
    /// than the display), and elements inside a cross-process remote view report
    /// frames local to that view. `hitPoint` is always a screen point — derived
    /// from the hit-test that found the element when one is available, otherwise
    /// the center of `frame` clipped to the screen.
    public var hitPoint: Frame.Point?
    /// Whether any part of the element is currently on screen. Off-screen
    /// elements are still listed (they exist, they are just scrolled away), but
    /// they cannot be touched until they are scrolled into view.
    public var onscreen: Bool?
    public var children: [AXNode]?

    public struct Frame: Codable, Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        /// A logical screen point, in the same space as a `Frame`.
        public struct Point: Codable, Equatable, Sendable {
            public var x: Double
            public var y: Double

            public init(x: Double, y: Double) {
                self.x = x
                self.y = y
            }
        }

        /// This frame clipped to `screen`, or nil when they do not overlap.
        public func intersected(with screen: Frame) -> Frame? {
            let minX = Swift.max(x, screen.x)
            let minY = Swift.max(y, screen.y)
            let maxX = Swift.min(x + width, screen.x + screen.width)
            let maxY = Swift.min(y + height, screen.y + screen.height)
            guard maxX > minX, maxY > minY else { return nil }
            return Frame(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
    }

    public init(
        AXLabel: String? = nil,
        AXValue: String? = nil,
        role_description: String? = nil,
        role: String? = nil,
        type: String? = nil,
        subrole: String? = nil,
        AXUniqueId: String? = nil,
        enabled: Bool? = nil,
        frame: Frame? = nil,
        hitPoint: Frame.Point? = nil,
        onscreen: Bool? = nil,
        children: [AXNode]? = nil
    ) {
        self.AXLabel = AXLabel
        self.AXValue = AXValue
        self.role_description = role_description
        self.role = role
        self.type = type
        self.subrole = subrole
        self.AXUniqueId = AXUniqueId
        self.enabled = enabled
        self.frame = frame
        self.hitPoint = hitPoint
        self.onscreen = onscreen
        self.children = children
    }
}
