// TapTargetCheck.swift
//
// Confirms that the point a selector resolved to actually reaches the element
// the selector matched, by hit-testing it before the touch is sent.
//
// Resolution works from frames, and a frame is a claim about where an element
// is, not proof that it can be touched there. A control can be clipped so that
// the visible slice of its frame is empty background; its accessible area can
// be smaller than the frame a layout modifier gave it; a scroll can move it
// between the read and the touch. In every one of those cases the injector
// happily delivers a touch to a coordinate with nothing behind it, the app sees
// nothing, and the command reports success — a test step that passes without
// ever having done anything.
//
// One hit-test at the resolved point settles the question this can actually
// answer: is there anything there at all? If the guest reports no element, the
// touch has nothing to land on and the action must say so instead of claiming
// success.
//
// It deliberately does NOT try to judge whether the element found is the "right"
// one. That judgement can only be made from frame geometry and identifiers, and
// both lie often enough to matter: a hit-test returns the deepest element, whose
// identifier differs from the actionable parent that will handle the touch;
// identifiers are not unique (SimBridge's own node keying refuses to rely on
// them); a frame that contains another proves nothing about accessibility
// ancestry; and inside a cross-process remote view the two frames are not even
// in the same coordinate space. Every rule tried for this rejected real,
// working taps on real screens. For a test harness a false failure is as
// damaging as a false pass, so the check claims only what it can prove.

import Foundation

public enum TapTargetCheck {
    public enum Outcome: Equatable, Sendable {
        /// The hit-test found an element — the touch has something to land on.
        case matches
        /// Nothing is at the point — the touch would be swallowed.
        case nothingThere

        public var isMatch: Bool { self == .matches }
    }

    /// Whether a touch at the resolved point would reach anything at all.
    ///
    /// `hit` is what the guest reports at that coordinate. See the file comment
    /// for why the identity of that element is deliberately not judged here.
    public static func evaluate(
        target: TapResolution,
        hit: AXNode?,
        screen: AXNode.Frame? = nil
    ) -> Outcome {
        hit == nil ? .nothingThere : .matches
    }

    /// A one-line explanation of why the touch was not sent.
    ///
    /// `undrivableScreen` names a screen the guest accepts no input on at all,
    /// when the caller knows of one. Without it the message blames the element,
    /// which on such a screen is wrong about every element on it — the reader
    /// goes looking for a clipped control that is not the problem.
    public static func describe(
        _ outcome: Outcome,
        selector: String,
        undrivableScreen: String? = nil
    ) -> String {
        switch outcome {
        case .matches:
            return ""
        case .nothingThere:
            if let undrivableScreen {
                return "\(selector) cannot be tapped: \(undrivableScreen)"
            }
            return "\(selector) resolved to a point with nothing behind it — the element is on screen but the part of it that is visible is not touchable (a clipped control, or an accessible frame larger than the control itself). The touch would have been discarded."
        }
    }

    /// Why the lit screen accepts no touches, or nil when nothing is known to be
    /// wrong with it.
    ///
    /// Measured on iPhone Duo / iOS 27.1, on a device created fresh for the
    /// test: with the device OPEN, the accessibility hit-test answers nothing at
    /// any of 49 points across the inner screen, and no touch at any of 70
    /// normalized points activates anything — while backboardd logs show the
    /// events arriving, so they are delivered and then discarded. Shut, the same
    /// device taps normally and a tap on its cover launches apps. The inner
    /// screen can be read and captured; it cannot be driven.
    ///
    /// This reports the pose, not a guess about the element, because on that
    /// screen every element fails the hit-test and none of them is at fault.
    public static func undrivableScreen(
        displays: [DeviceDisplay]
    ) -> String? {
        guard displays.count > 1,
              let lit = DisplaySelection.active(displays),
              DisplaySelection.roles(displays)[lit.screenID] == .inner
        else { return nil }
        return "an iPhone Duo's inner screen takes no input in Xcode 27.1 — the "
            + "accessibility hit-test answers nothing anywhere on it and touches are "
            + "discarded. Reading and screenshots work. Run `sipi fold <udid> --closed` "
            + "to drive the app on the cover screen instead."
    }
}
