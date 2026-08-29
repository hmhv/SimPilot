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
    public static func describe(_ outcome: Outcome, selector: String) -> String {
        switch outcome {
        case .matches:
            return ""
        case .nothingThere:
            return "\(selector) resolved to a point with nothing behind it — the element is on screen but the part of it that is visible is not touchable (a clipped control, or an accessible frame larger than the control itself). The touch would have been discarded."
        }
    }
}
