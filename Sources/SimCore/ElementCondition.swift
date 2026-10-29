// ElementCondition.swift
//
// Whether an element matching a selector is on screen (or gone), judged against
// the node tree rather than the serialized text, so a label that only appears
// inside another element's value cannot satisfy it.
//
// Pure Foundation: no SimBridge, no private frameworks, fully unit-testable.

import Foundation

/// An assertion that an element matching the selector exists, or with
/// `exists: false` that none does. The selector fields (`id`, `label`, `value`,
/// `elementType`) are ANDed.
public struct ElementCondition: Equatable, Sendable {
    public var id: String?
    public var label: String?
    public var value: String?
    public var elementType: String?
    /// Defaults to true; set false to assert the element is gone (evaluated
    /// against the deep tree, like `absent`).
    public var exists: Bool?

    public init(
        id: String? = nil,
        label: String? = nil,
        value: String? = nil,
        elementType: String? = nil,
        exists: Bool? = nil
    ) {
        self.id = id
        self.label = label
        self.value = value
        self.elementType = elementType
        self.exists = exists
    }

    /// Whether this condition asserts absence, which — like `absent` — is only
    /// trustworthy against the deep tree.
    public var assertsAbsence: Bool { exists == false }

    /// Human-readable selector, used in the row text.
    public var selectorDescription: String {
        var parts: [String] = []
        if let id { parts.append("id=\(id)") }
        if let label { parts.append("label=\(label)") }
        if let value { parts.append("value=\(value)") }
        if let elementType { parts.append("type=\(elementType)") }
        return parts.isEmpty ? "<no selector>" : parts.joined(separator: " ")
    }

    /// Evaluate against a tree. Returns nil on success, or the reason it failed.
    public func failureReason(in roots: [AXNode]) -> String? {
        let matched = matches(in: roots)
        if assertsAbsence {
            return matched.isEmpty ? nil : "expected no match, found \(matched.count)"
        }
        return matched.isEmpty ? "no element matched" : nil
    }

    /// Elements matching the selector. String comparisons are exact after
    /// trimming, matching how the tap resolver reads labels.
    func matches(in roots: [AXNode]) -> [AXNode] {
        roots.flatMap { $0.flattened() }.filter { node in
            if let id, AXNode.trimmed(node.AXUniqueId) != id { return false }
            if let label, AXNode.trimmed(node.AXLabel) != label { return false }
            if let value, AXNode.trimmed(node.AXValue) != value { return false }
            if let elementType, node.type != elementType { return false }
            return true
        }
    }
}
