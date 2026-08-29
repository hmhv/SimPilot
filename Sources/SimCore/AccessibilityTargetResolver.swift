// AccessibilityTargetResolver.swift
//
// Adapted for SimPilot from AXe (https://github.com/cameroncooke/AXe),
// origin: Sources/AXe/Utilities/AccessibilityTargetResolver.swift — MIT License
// (Copyright (c) 2025 Cameron Cooke; see THIRD_PARTY_LICENSES.md).
//
// A Foundation-only lift, not a rewrite. The resolution algorithm — selector
// matching, switch/toggle preference, actionable-ancestor sibling redirect, and
// the wide-switch trailing-inset activation point — is preserved exactly. The
// only adaptation is the element model:
// AXe's private `AccessibilityElement` is replaced by SimCore.AXNode (the
// describe-ui contract model) and the activation point is returned as a
// SimCore.Point instead of an (x, y) tuple.

import Foundation

/// A selector for an accessibility element. Mirrors AXe's AccessibilityQuery.
public enum AccessibilityQuery: Equatable, Sendable {
    case id(String)
    case label(String)
    case value(String)

    /// Only label queries may redirect to a sibling switch under a shared
    /// ancestor (a label often sits next to the control it describes).
    var allowsSiblingRedirection: Bool {
        switch self {
        case .label:
            return true
        case .id, .value:
            return false
        }
    }
}

/// Errors surfaced while resolving a selector to a target element.
public enum ElementResolutionError: Error, CustomStringConvertible, Equatable {
    case notFound(kind: String, value: String)
    case multipleMatches(count: Int, kind: String, value: String, hasUniqueIDs: Bool)
    case invalidFrame(reason: String)
    case multipleSwitchDescendants(count: Int, selectorDescription: String)

    public var description: String {
        let tip = AccessibilityTargetResolver.describeUITip
        switch self {
        case .notFound(let kind, let value):
            return "No accessibility element matched \(kind) '\(value)'. \(tip)"
        case .multipleMatches(let count, let kind, let value, let hasUniqueIDs):
            if hasUniqueIDs {
                return "Multiple (\(count)) accessibility elements matched \(kind) '\(value)'. Use --id when labels are not unique. \(tip)"
            }
            return "Multiple (\(count)) accessibility elements matched \(kind) '\(value)', and none of the matches expose AXUniqueId on this screen. Use coordinates for this step (tap -x/-y) or target a more specific screen/state. \(tip)"
        case .invalidFrame(let reason):
            return "\(reason) \(tip)"
        case .multipleSwitchDescendants(let count, let selectorDescription):
            return "Matched element for \(selectorDescription) contains multiple (\(count)) switch/toggle controls. Target the switch more specifically with --id when available, or use coordinates. \(tip)"
        }
    }

    public var isNotFound: Bool {
        if case .notFound = self { return true }
        return false
    }
}

/// A resolved selector match: the element, a human-readable selector
/// description, and the application frame (for coordinate context).
public struct AccessibilityMatch: Equatable, Sendable {
    public let element: AXNode
    public let selectorDescription: String
    public let applicationFrame: AXNode.Frame?

    public init(element: AXNode, selectorDescription: String, applicationFrame: AXNode.Frame?) {
        self.element = element
        self.selectorDescription = selectorDescription
        self.applicationFrame = applicationFrame
    }
}

public enum AccessibilityTargetResolver {
    public static let describeUITip = "Make sure the app is on the expected screen, then run `sipi describe-ui <SIMULATOR_UDID>` and prefer --id when available."

    private static let wideSwitchActivationWidthThreshold = 100.0
    private static let switchTrailingActivationInset = 31.0

    public static func resolveTapPoint(
        roots: [AXNode],
        query: AccessibilityQuery,
        elementType: String? = nil
    ) throws -> Point {
        try resolveTap(roots: roots, query: query, elementType: elementType).point
    }

    public static func resolveElement(
        roots: [AXNode],
        query: AccessibilityQuery,
        elementType: String? = nil
    ) throws -> AccessibilityMatch {
        var allElements = roots.flatMap { $0.flattened() }

        if let elementType {
            allElements = allElements.filter { $0.type == elementType }
        }

        let matchedElement: AXNode
        let selectorDescription: String

        switch query {
        case .id(let rawValue):
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let matches = allElements.filter { $0.normalizedUniqueId == value }
            matchedElement = try selectUniqueMatch(matches, kind: "--id", value: rawValue)
            selectorDescription = "--id '\(rawValue)'"
        case .label(let rawValue):
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let matches = allElements.filter { $0.normalizedLabel == value }
            matchedElement = try selectBestLabelMatch(matches, value: rawValue)
            selectorDescription = "--label '\(rawValue)'"
        case .value(let rawValue):
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let matches = allElements.filter { $0.normalizedValue == value }
            matchedElement = try selectBestLabelMatch(matches, kind: "--value", value: rawValue)
            selectorDescription = "--value '\(rawValue)'"
        }

        return AccessibilityMatch(
            element: matchedElement,
            selectorDescription: selectorDescription,
            applicationFrame: applicationFrame(from: roots)
        )
    }

    public static func resolveTap(
        roots: [AXNode],
        query: AccessibilityQuery,
        elementType: String? = nil
    ) throws -> TapResolution {
        let match = try resolveElement(roots: roots, query: query, elementType: elementType)

        let activationElement = try selectActivationElement(
            from: match.element,
            roots: roots,
            selectorDescription: match.selectorDescription,
            allowSiblingRedirection: query.allowsSiblingRedirection
        )

        guard let frame = activationElement.frame else {
            throw ElementResolutionError.invalidFrame(reason: "Matched element has no frame.")
        }
        guard frame.width > 0, frame.height > 0 else {
            throw ElementResolutionError.invalidFrame(reason: "Matched element has an invalid frame size (\(frame.width)x\(frame.height)).")
        }

        let screen = applicationFrame(from: roots)
        return TapResolution(
            point: activationPoint(for: activationElement, frame: frame, screen: screen),
            isSwitchLikeControl: activationElement.isSwitchLikeControl,
            isOnScreen: isReachable(activationElement, frame: frame, screen: screen),
            frame: frame,
            identifier: activationElement.AXUniqueId,
            label: activationElement.AXLabel
        )
    }

    /// Whether the element can be touched at all right now: some part of it is
    /// inside the display, or the driver measured a hit point for it (which only
    /// happens when a hit-test on screen actually reached it).
    private static func isReachable(
        _ element: AXNode,
        frame: AXNode.Frame,
        screen: AXNode.Frame?
    ) -> Bool {
        // `onscreen` is computed against the display, so it is the authority
        // even when a hit point exists: a probe on the very edge of the grid can
        // sit on the exclusive boundary, which is not a touchable coordinate.
        if let onscreen = element.onscreen { return onscreen }
        if element.hitPoint != nil { return true }
        guard let screen else { return true }
        return frame.intersected(with: screen) != nil
    }

    /// The point to touch for this element.
    ///
    /// A hit point that lies OUTSIDE the element's own frame can only have come
    /// from a hit-test that actually reached the element — the driver records
    /// one when the frame turns out not to be in screen coordinates at all,
    /// which is the case inside a cross-process remote view such as the share
    /// sheet. There the frame is unusable and the measured point is the only way
    /// in, so it wins outright.
    ///
    /// A hit point inside the frame is just the clipped center the driver
    /// computed, and carries no more information than the frame does. Ignoring
    /// it here keeps the switch/toggle rule below alive: a wide switch row must
    /// be tapped near its trailing edge, where the knob is, not at its center.
    ///
    /// Otherwise the frame is clipped to the display first, so an element that
    /// runs past the edge is touched where it is actually visible instead of at
    /// a center that may be off screen.
    private static func activationPoint(
        for element: AXNode,
        frame: AXNode.Frame,
        screen: AXNode.Frame?
    ) -> Point {
        if let measured = element.hitPoint, !frame.contains(measured) {
            return Point(x: measured.x, y: measured.y)
        }

        let visible = screen.flatMap { frame.intersected(with: $0) } ?? frame
        let centerY = visible.y + (visible.height / 2.0)

        // The trailing inset is measured from the element's own trailing edge —
        // that is where the switch knob sits — but it has to stay inside the
        // visible slice, or a switch running off the right edge would be tapped
        // off screen.
        if element.isSwitchLikeControl, frame.width > wideSwitchActivationWidthThreshold {
            let trailing = frame.x + frame.width - switchTrailingActivationInset
            // The visible slice is half-open, so its own maximum is the first
            // coordinate NOT on the element: clamp inside it, never onto it.
            let inset = min(0.5, visible.width / 2.0)
            let clamped = min(max(trailing, visible.x), visible.x + visible.width - inset)
            return Point(x: clamped, y: centerY)
        }

        return Point(x: visible.x + (visible.width / 2.0), y: centerY)
    }

    private static func applicationFrame(from roots: [AXNode]) -> AXNode.Frame? {
        roots.first { $0.type == "Application" }?.frame ?? roots.first?.frame
    }

    private static func selectUniqueMatch(
        _ matches: [AXNode],
        kind: String,
        value: String
    ) throws -> AXNode {
        guard !matches.isEmpty else {
            throw ElementResolutionError.notFound(kind: kind, value: value)
        }
        guard matches.count == 1 else {
            let hasUniqueIDs = matches.contains {
                guard let id = $0.normalizedUniqueId else { return false }
                return !id.isEmpty
            }
            throw ElementResolutionError.multipleMatches(count: matches.count, kind: kind, value: value, hasUniqueIDs: hasUniqueIDs)
        }
        return matches[0]
    }

    private static func selectBestLabelMatch(
        _ matches: [AXNode],
        kind: String = "--label",
        value: String
    ) throws -> AXNode {
        let switchLikeMatches = matches.filter(\.isSwitchLikeControl)
        if switchLikeMatches.count == 1 {
            return switchLikeMatches[0]
        }
        if switchLikeMatches.count > 1 {
            return try selectUniqueMatch(switchLikeMatches, kind: kind, value: value)
        }

        let actionableMatches = matches.filter(\.isActionable)
        if actionableMatches.count == 1 {
            return actionableMatches[0]
        }

        if actionableMatches.count > 1 {
            return try selectUniqueMatch(actionableMatches, kind: kind, value: value)
        }

        return try selectUniqueMatch(matches, kind: kind, value: value)
    }

    private static func selectActivationElement(
        from matchedElement: AXNode,
        roots: [AXNode],
        selectorDescription: String,
        allowSiblingRedirection: Bool
    ) throws -> AXNode {
        if matchedElement.isSwitchLikeControl {
            return matchedElement
        }

        let switchDescendants = matchedElement.switchLikeDescendantsIncludingSelf()
        if !switchDescendants.isEmpty {
            guard switchDescendants.count == 1 else {
                throw ElementResolutionError.multipleSwitchDescendants(
                    count: switchDescendants.count,
                    selectorDescription: selectorDescription
                )
            }
            return switchDescendants[0]
        }

        if matchedElement.isActionable {
            return matchedElement
        }

        if allowSiblingRedirection, let ancestor = nearestAncestor(of: matchedElement, in: roots) {
            let siblingSwitches = directSwitchLikeChildren(of: ancestor)
            if siblingSwitches.count == 1 {
                return siblingSwitches[0]
            }
        }

        return matchedElement
    }

    private static func directSwitchLikeChildren(of element: AXNode) -> [AXNode] {
        element.children?.filter(\.isSwitchLikeControl) ?? []
    }

    private static func nearestAncestor(
        of matchedElement: AXNode,
        in roots: [AXNode]
    ) -> AXNode? {
        for root in roots {
            if let ancestor = nearestAncestor(of: matchedElement, in: root, parent: nil) {
                return ancestor
            }
        }
        return nil
    }

    private static func nearestAncestor(
        of matchedElement: AXNode,
        in currentElement: AXNode,
        parent: AXNode?
    ) -> AXNode? {
        if sameElement(currentElement, matchedElement) {
            return parent
        }

        for child in currentElement.children ?? [] {
            if let ancestor = nearestAncestor(of: matchedElement, in: child, parent: currentElement) {
                return ancestor
            }
        }
        return nil
    }

    private static func sameElement(_ lhs: AXNode, _ rhs: AXNode) -> Bool {
        if let lhsID = lhs.normalizedStableUniqueId, let rhsID = rhs.normalizedStableUniqueId {
            return lhsID == rhsID
        }

        guard lhs.type == rhs.type,
              lhs.normalizedLabel == rhs.normalizedLabel,
              lhs.normalizedValue == rhs.normalizedValue,
              sameFrame(lhs.frame, rhs.frame) else {
            return false
        }

        if lhs.normalizedLabel == nil && lhs.normalizedValue == nil {
            return lhs.role == rhs.role
                && lhs.role_description == rhs.role_description
                && lhs.subrole == rhs.subrole
        }

        return true
    }

    private static func sameFrame(_ lhs: AXNode.Frame?, _ rhs: AXNode.Frame?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        return lhs.x == rhs.x
            && lhs.y == rhs.y
            && lhs.width == rhs.width
            && lhs.height == rhs.height
    }
}
