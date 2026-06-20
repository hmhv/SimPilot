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
public enum HardwareButton: String, Codable, Sendable {
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
        self.children = children
    }
}
