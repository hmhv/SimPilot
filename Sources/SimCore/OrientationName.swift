// OrientationName.swift
//
// Pure-logic mapping for the orientation SET path. Maps the orientation names
// the CLI accepts to: (a) the UIDeviceOrientation 1...4 set the native
// PurpleEvent SET can express, and (b) the Simulator "Device > Orientation"
// menu item label used by the osascript fallback (which also covers face-up /
// face-down, since PurpleEvent cannot express those).
//
// No SimBridge, no Process(), no private frameworks — this stays unit-testable
// and keeps the name canonicalization in one place shared by the READ and SET.

import Foundation

/// A requested device orientation for the SET path, parsed from a CLI name.
public enum OrientationSetName: Equatable, Sendable {
    case portrait
    case portraitUpsideDown
    case landscapeLeft
    case landscapeRight
    case faceUp
    case faceDown

    /// Parse a CLI orientation name. Accepts the canonical hyphenated names plus
    /// the short aliases (`left`, `right`, `landscape`) and underscore variants.
    /// Returns nil for an unknown name.
    public init?(_ raw: String) {
        let normalized = raw.lowercased().replacingOccurrences(of: "_", with: "-")
        switch normalized {
        case "portrait":
            self = .portrait
        case "portrait-upside-down", "upside-down":
            self = .portraitUpsideDown
        case "landscape-left", "left":
            self = .landscapeLeft
        case "landscape-right", "right", "landscape":
            self = .landscapeRight
        case "face-up":
            self = .faceUp
        case "face-down":
            self = .faceDown
        default:
            return nil
        }
    }

    /// Whether the native PurpleEvent SET can express this orientation. PurpleEvent
    /// covers only UIDeviceOrientation 1...4, so face-up / face-down always go
    /// through the osascript menu path.
    public var isNativeExpressible: Bool {
        switch self {
        case .portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight:
            return true
        case .faceUp, .faceDown:
            return false
        }
    }

    /// The canonical lowercase name passed to the native SET (the same names the
    /// READ emits / `SPSimBridge.setOrientationNative` accepts).
    public var canonicalName: String {
        switch self {
        case .portrait: return "portrait"
        case .portraitUpsideDown: return "portrait-upside-down"
        case .landscapeLeft: return "landscape-left"
        case .landscapeRight: return "landscape-right"
        case .faceUp: return "face-up"
        case .faceDown: return "face-down"
        }
    }

    /// The Simulator "Device > Orientation" submenu item label used by the
    /// osascript fallback.
    public var menuItemName: String {
        switch self {
        case .portrait: return "Portrait"
        case .portraitUpsideDown: return "Portrait Upside Down"
        case .landscapeLeft: return "Landscape Left"
        case .landscapeRight: return "Landscape Right"
        case .faceUp: return "Face Up"
        case .faceDown: return "Face Down"
        }
    }

    /// The orientation names the CLI accepts, for help text / validation messages.
    public static let acceptedNames = "portrait, portrait-upside-down, landscape-left, landscape-right, face-up, face-down"
}
