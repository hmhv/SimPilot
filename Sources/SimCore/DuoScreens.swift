// DuoScreens.swift
//
// What sipi can and cannot do on each of iPhone Duo's two screens.
//
// Measured on Xcode 27.2 RC (27B48) / iOS 27.2 (24B91014), driving Settings and
// Safari, with touches sent to the lit screen's own digitizer:
//
//   cover  Taps by point and by selector, swipes, long presses, typing,
//          set-text, the hit-test and hardware buttons all work, upright and
//          on its side.
//   inner  Taps by point, swipes, long presses, typing and hardware buttons
//          work. The accessibility hit-test answers nothing anywhere on it, so a
//          selector tap cannot be checked against what is under the point, and
//          set-text and describe-point — both built on the hit-test — cannot
//          work at all.
//
// On both, rotation cannot be scripted (Device Hub's rotate button can), and
// Xcode's device-interaction service reaches the cover only.

import Foundation

public enum DuoScreens {
    /// Which of a two-screen device's screens is lit, or nil for a device with
    /// one screen, an asleep one, or screens that could not be read.
    public static func litRole(_ displays: [DeviceDisplay]) -> DisplayRole? {
        guard displays.count > 1, let lit = DisplaySelection.active(displays) else { return nil }
        return DisplaySelection.roles(displays)[lit.screenID]
    }

    public static func isInnerLit(_ displays: [DeviceDisplay]) -> Bool {
        litRole(displays) == .inner
    }

    /// Said in place of blaming the element when a hit-test comes back empty
    /// on the inner screen: there, every element answers that way.
    public static let innerHitTest = "an iPhone Duo's inner screen answers no accessibility hit-test"

    /// One line per screen, for `sipi doctor`.
    public static let summary: [String] = [
        "cover: taps by point or selector, swipes, long presses, typing, set-text, "
            + "describe-point and hardware buttons all work.",
        "inner: taps by point, swipes, long presses, typing and hardware buttons work. "
            + "A selector tap goes to the element's frame unchecked, because \(innerHitTest); "
            + "for the same reason set-text and describe-point do not work there — fold it shut for those.",
        "both: rotation cannot be scripted (Device Hub's rotate button can), and "
            + "`--xcode-mcp` reaches the cover only."
    ]
}
