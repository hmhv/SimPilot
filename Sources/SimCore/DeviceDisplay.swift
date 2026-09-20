// DeviceDisplay.swift
//
// The screens a device has built in, and the rules for choosing between them.
//
// Every simulator before iPhone Duo (Xcode 27.1) had exactly one, so "the
// screen" needed no naming and no choosing: a capture went to the one
// framebuffer, and `SimDeviceScreen initWithDevice:screenID:1` read the one
// orientation. A Duo has two — a 1398x2034 cover and a 2007x2853 inner screen —
// and lights exactly one of them at a time. The dark one still vends a live,
// solid-black framebuffer, so picking the wrong one is not an error anywhere in
// the stack: it is a black PNG, an accessibility tree for a screen nobody is
// looking at, and gestures rotated by an orientation that belongs to neither.
//
// Which screen is lit changes whenever the device folds — in Device Hub, or
// through `sipi fold` (see SimShell's HingeControl). Either way nothing
// announces it, so this is read every time it matters rather than resolved
// once.

import Foundation

/// One screen built into the device.
public struct DeviceDisplay: Equatable, Sendable {
    /// The CoreSimulator screen ID: what `simctl io --display` takes and what
    /// `SimDeviceScreen initWithDevice:screenID:` reads. iPhone Duo uses 1 for
    /// the cover and 3 for the inner screen.
    public var screenID: Int
    /// The system's name for the screen — "LCD", "LCD-1".
    public var name: String
    /// Framebuffer size in pixels, UNROTATED. A capture of this screen comes
    /// back at exactly these dimensions whatever way up the device is.
    public var pixelWidth: Int
    public var pixelHeight: Int
    /// Pixels per point; 3 on every screen measured so far.
    public var pointScale: Int
    /// Whether the device is lighting this screen right now, or nil when the
    /// system does not say.
    ///
    /// devicectl reports this only for a device with more than one built-in
    /// screen — where there is something to choose between. A phone's one screen
    /// carries no flag at all, and nil there means "not reported", NOT "off": the
    /// one screen is the one being used whatever state it is in.
    public var active: Bool?
    /// Whether the system treats this as the device's main screen. On iPhone Duo
    /// the COVER is primary, not the larger inner screen — so "primary" is not a
    /// synonym for "the big one" and not a synonym for "lit".
    public var primary: Bool
    /// `rot0` / `rot90` / `rot180` / `rot270`, or nil when unreported. A screen
    /// that is switched off keeps reporting whatever it last showed, so this is
    /// only meaningful for the active screen.
    public var rotation: String?

    public init(
        screenID: Int,
        name: String = "",
        pixelWidth: Int,
        pixelHeight: Int,
        pointScale: Int = 1,
        active: Bool? = nil,
        primary: Bool = false,
        rotation: String? = nil
    ) {
        self.screenID = screenID
        self.name = name
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.pointScale = pointScale
        self.active = active
        self.primary = primary
        self.rotation = rotation
    }

    /// The screen size in points — the space `describe-ui` frames and tap
    /// coordinates live in.
    public var pointWidth: Int { pixelWidth / max(pointScale, 1) }
    public var pointHeight: Int { pixelHeight / max(pointScale, 1) }

    public var pixelArea: Int { pixelWidth * pixelHeight }

    /// The size of the space `describe-ui` frames and tap coordinates live in,
    /// for a device held in `orientation`: this screen's point size, read
    /// width-for-height when the UI is on its side.
    ///
    /// This is the screen's own geometry, which is a fact. The accessibility
    /// root's frame is the usual proxy for it and agrees exactly on a device
    /// with one screen — measured on iPhone 17 / iOS 27.0, a 402x874 panel
    /// reports a 402x874 root in portrait and an 874x402 root in landscape-left.
    /// It does NOT agree on an iPhone Duo's inner screen, which sits in
    /// landscape and reports the unrotated 669x951 panel as its root while its
    /// elements are laid out in the 951x669 space around it — a button spanning
    /// to x=844 on a root that claims to be 669 wide.
    public func logicalExtent(in orientation: UIOrientation) -> (width: Int, height: Int) {
        orientation.isLandscape
            ? (pointHeight, pointWidth)
            : (pointWidth, pointHeight)
    }
}

/// What a screen is for, on the device it belongs to.
public enum DisplayRole: String, Sendable {
    /// The device has one built-in screen, so there is nothing to distinguish.
    case screen
    /// A foldable's large inside screen, usable only while the device is open.
    case inner
    /// A foldable's outside screen, usable while it is shut.
    case cover
}

/// Choosing a screen: naming the roles, reading which one is lit, and resolving
/// what a caller typed after `--display`.
public enum DisplaySelection {

    /// Role per screen ID.
    ///
    /// One screen is just `screen`. Two are a foldable: the larger is the inner
    /// screen and the smaller is the cover. Size is the discriminator rather
    /// than `primary` (the Duo's cover is primary) or the screen ID (1 is the
    /// cover, 3 is the inner screen — neither ordered nor contiguous).
    ///
    /// Three or more is a device this build has never seen; every screen gets
    /// `screen` rather than a guessed role, so a caller can still address them
    /// by ID.
    public static func roles(_ displays: [DeviceDisplay]) -> [Int: DisplayRole] {
        guard displays.count == 2 else {
            return Dictionary(uniqueKeysWithValues: displays.map { ($0.screenID, DisplayRole.screen) })
        }
        let sorted = displays.sorted { $0.pixelArea < $1.pixelArea }
        return [sorted[0].screenID: .cover, sorted[1].screenID: .inner]
    }

    /// The screen the device is lighting, or nil when nothing says which.
    ///
    /// `primary` is NOT a fallback here: on a Duo it names the cover whichever
    /// way the device is folded, so falling back to it would answer "cover"
    /// about a device that is open. A caller that must have an answer decides
    /// for itself what to do with nil.
    ///
    /// A device with one screen reports no flag at all, and that one screen is
    /// the answer — including while it is asleep. Reading absence as "off" there
    /// would refuse to capture every non-foldable that had dimmed.
    public static func active(_ displays: [DeviceDisplay]) -> DeviceDisplay? {
        if let flagged = displays.first(where: { $0.active == true }) { return flagged }
        if displays.count == 1, displays[0].active == nil { return displays[0] }
        return nil
    }

    /// Whether the device is shut, or nil when the question does not apply
    /// (one screen) or cannot be answered (nothing lit).
    ///
    /// Shut means the cover is the lit screen. This is derived from which screen
    /// is on rather than from the hinge angle, because the angle is a continuous
    /// value with no documented threshold — a Duo reads 0 shut and 130 at the
    /// angle Device Hub calls open, and nothing says where between those the
    /// system hands over.
    public static func isFolded(_ displays: [DeviceDisplay]) -> Bool? {
        guard displays.count == 2, let lit = active(displays) else { return nil }
        return roles(displays)[lit.screenID] == .cover
    }

    /// What a caller may write after `--display`.
    public enum Selector: Equatable, Sendable {
        /// Whichever screen is lit. The default, and the only sane one for a
        /// device that can fold while a run is in progress.
        case active
        case role(DisplayRole)
        case screenID(Int)
    }

    public static let selectorSyntax = "active | inner | cover | <screen id>"

    /// Parse a `--display` value, or nil when it is none of the accepted forms.
    public static func parseSelector(_ raw: String) -> Selector? {
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "active": return .active
        case "inner": return .role(.inner)
        case "cover": return .role(.cover)
        case let other:
            guard let id = Int(other), id > 0 else { return nil }
            return .screenID(id)
        }
    }

    public enum ResolutionError: Error, CustomStringConvertible {
        case noneActive(available: [String])
        case noSuchRole(DisplayRole, available: [String])
        case noSuchScreenID(Int, available: [String])

        public var description: String {
            switch self {
            case .noneActive(let available):
                return "no screen is currently lit on this device (it may be asleep); "
                    + "name one instead: \(available.joined(separator: ", "))"
            case .noSuchRole(let role, let available):
                return "this device has no '\(role.rawValue)' screen; it has: "
                    + available.joined(separator: ", ")
            case .noSuchScreenID(let id, let available):
                return "this device has no screen \(id); it has: " + available.joined(separator: ", ")
            }
        }
    }

    /// The screen a selector names.
    public static func resolve(
        _ selector: Selector,
        in displays: [DeviceDisplay]
    ) throws -> DeviceDisplay {
        let roles = roles(displays)
        let available = displays.map { display -> String in
            let role = roles[display.screenID] ?? .screen
            let label = role == .screen ? "" : " (\(role.rawValue))"
            return "\(display.screenID)\(label) \(display.pixelWidth)x\(display.pixelHeight)"
        }
        switch selector {
        case .active:
            guard let lit = active(displays) else {
                throw ResolutionError.noneActive(available: available)
            }
            return lit
        case .role(let wanted):
            guard let match = displays.first(where: { roles[$0.screenID] == wanted }) else {
                throw ResolutionError.noSuchRole(wanted, available: available)
            }
            return match
        case .screenID(let id):
            guard let match = displays.first(where: { $0.screenID == id }) else {
                throw ResolutionError.noSuchScreenID(id, available: available)
            }
            return match
        }
    }
}
