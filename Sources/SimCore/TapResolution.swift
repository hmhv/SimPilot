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

    public init(point: Point, isSwitchLikeControl: Bool) {
        self.point = point
        self.isSwitchLikeControl = isSwitchLikeControl
    }
}
