// TapResolution.swift
//
// Adapted for SimPilot from AXe (https://github.com/cameroncooke/AXe),
// origin: Sources/AXe/Types/TapStyle.swift — MIT License
// (Copyright (c) 2025 Cameron Cooke; see THIRD_PARTY_LICENSES.md).
//
// AXe's TapStyle.swift also declares a `TapStyle` enum that conforms to
// ArgumentParser's ExpressibleByArgument, so the whole file imports
// ArgumentParser. SimCore must stay dependency-clean (Foundation only), so only
// the unrelated `TapResolution` struct is extracted here — the enum is not
// ported.

import Foundation

/// The result of resolving a selector to a tappable target: the activation
/// point in the simulator's logical coordinate space, plus whether the resolved
/// element is a switch/toggle (callers use this to drive the right interaction).
public struct TapResolution: Equatable, Sendable {
    public let point: Point
    public let isSwitchLikeControl: Bool
    /// Whether the resolved element is on screen right now. `describe-ui` lists
    /// elements that have scrolled out of view, and touching one of those sends
    /// the touch to a coordinate the display does not have: the injector accepts
    /// it, the app never sees it, and the action looks like it worked. Callers
    /// must bring the element into view (or fail) rather than tap a point that
    /// cannot land.
    public let isOnScreen: Bool
    /// The resolved element's own frame, for diagnostics when it is off screen
    /// and for deciding which way to scroll.
    public let frame: AXNode.Frame?
    /// The resolved element's accessibility identifier, used to confirm that a
    /// hit-test at `point` really reaches this element before touching it.
    public let identifier: String?
    /// The resolved element's label, used for the same confirmation when it has
    /// no identifier.
    public let label: String?

    public init(
        point: Point,
        isSwitchLikeControl: Bool,
        isOnScreen: Bool = true,
        frame: AXNode.Frame? = nil,
        identifier: String? = nil,
        label: String? = nil
    ) {
        self.point = point
        self.isSwitchLikeControl = isSwitchLikeControl
        self.isOnScreen = isOnScreen
        self.frame = frame
        self.identifier = identifier
        self.label = label
    }
}
