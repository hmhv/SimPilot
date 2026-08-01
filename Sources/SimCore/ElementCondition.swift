// ElementCondition.swift
//
// Structured verify conditions: assertions about ELEMENTS rather than about the
// raw accessibility-tree text.
//
// `contains` / `absent` grep the serialized tree, which is cheap and honest
// about what is on screen but cannot express "the Submit button is disabled",
// "there are exactly five rows", or "this control meets the 44pt touch target".
// Those need the node structure, so they are evaluated against `[AXNode]`.
//
// This is where the harness beats a model reading a screenshot: every assertion
// here is decidable, reproducible, and explains its own failure with the value
// it actually observed.
//
// Pure Foundation: no SimBridge, no private frameworks, fully unit-testable.

import Foundation

/// A structured assertion about the elements matching a selector.
///
/// The selector fields (`id`, `label`, `value`, `elementType`) are ANDed to pick
/// the element set; the assertion fields then describe what must be true of that
/// set. At least one selector field is required — an assertion with no selector
/// would silently apply to the whole screen.
public struct ElementCondition: Equatable, Sendable {
    // Selector
    public var id: String?
    public var label: String?
    public var value: String?
    public var elementType: String?

    // Assertions
    /// Whether any element must match. Defaults to true; set false to assert the
    /// element is gone (evaluated against the deep tree, like `absent`).
    public var exists: Bool?
    /// Required `enabled` state for every matching element.
    public var enabled: Bool?
    /// Required exact AXValue for every matching element.
    public var valueEquals: String?
    /// Regular expression every matching element's AXValue must match.
    public var valueMatches: String?
    /// Exact number of matching elements.
    public var count: Int?
    public var minCount: Int?
    public var maxCount: Int?
    /// Minimum frame extent in points for every matching element — the assertion
    /// form of the `hit-region` audit rule.
    public var minWidth: Double?
    public var minHeight: Double?

    public init(
        id: String? = nil,
        label: String? = nil,
        value: String? = nil,
        elementType: String? = nil,
        exists: Bool? = nil,
        enabled: Bool? = nil,
        valueEquals: String? = nil,
        valueMatches: String? = nil,
        count: Int? = nil,
        minCount: Int? = nil,
        maxCount: Int? = nil,
        minWidth: Double? = nil,
        minHeight: Double? = nil
    ) {
        self.id = id
        self.label = label
        self.value = value
        self.elementType = elementType
        self.exists = exists
        self.enabled = enabled
        self.valueEquals = valueEquals
        self.valueMatches = valueMatches
        self.count = count
        self.minCount = minCount
        self.maxCount = maxCount
        self.minWidth = minWidth
        self.minHeight = minHeight
    }

    /// Whether this condition asserts absence, which — like `absent` — is only
    /// trustworthy against the deep tree.
    public var assertsAbsence: Bool {
        exists == false || count == 0 || maxCount == 0
    }

    /// Human-readable selector, used in the verify row text.
    public var selectorDescription: String {
        var parts: [String] = []
        if let id { parts.append("id=\(id)") }
        if let label { parts.append("label=\(label)") }
        if let value { parts.append("value=\(value)") }
        if let elementType { parts.append("type=\(elementType)") }
        return parts.isEmpty ? "<no selector>" : parts.joined(separator: " ")
    }

    /// Human-readable assertion list, used in the verify row text.
    public var assertionDescription: String {
        var parts: [String] = []
        if let exists { parts.append(exists ? "exists" : "absent") }
        if let enabled { parts.append("enabled=\(enabled)") }
        if let valueEquals { parts.append("value=\(valueEquals)") }
        if let valueMatches { parts.append("value~=\(valueMatches)") }
        if let count { parts.append("count=\(count)") }
        if let minCount { parts.append("min-count=\(minCount)") }
        if let maxCount { parts.append("max-count=\(maxCount)") }
        if let minWidth { parts.append("min-width=\(Int(minWidth))") }
        if let minHeight { parts.append("min-height=\(Int(minHeight))") }
        // A bare selector with no assertion means "must exist".
        return parts.isEmpty ? "exists" : parts.joined(separator: ", ")
    }

    /// Every selector field that is set, for validation.
    public var hasSelector: Bool {
        id != nil || label != nil || value != nil || elementType != nil
    }

    /// Evaluate against a tree. Returns nil on success, or the reason it failed.
    ///
    /// Failure messages report what was actually observed, so a failing run does
    /// not require re-reading the describe dump to understand.
    public func failureReason(in roots: [AXNode]) -> String? {
        let matched = matches(in: roots)

        // Existence is checked first: every other assertion is vacuous without a
        // match, and reporting "0 of 0 elements are enabled" would read as a pass.
        //
        // `assertsAbsence` is the single definition of "this condition expects
        // nothing to match" — the same one `VerifyEvaluator.requiresDeep` uses to
        // decide the deep fetch. Reusing it here keeps the two from drifting: a
        // form that forces a deep tree because it asserts absence must also be
        // EVALUATED as an absence assertion, or `max-count: 0` would fall through
        // to the "no element matched" failure below and fail on exactly the screen
        // it was written to accept.
        if assertsAbsence {
            return matched.isEmpty ? nil : "expected no match, found \(matched.count)"
        }
        if let count {
            guard matched.count == count else {
                return "expected \(count) matching element(s), found \(matched.count)"
            }
        }
        if matched.isEmpty {
            return "no element matched"
        }
        if let minCount, matched.count < minCount {
            return "expected at least \(minCount) matching element(s), found \(matched.count)"
        }
        if let maxCount, matched.count > maxCount {
            return "expected at most \(maxCount) matching element(s), found \(matched.count)"
        }
        if let enabled {
            // `enabled` is optional in the tree; an element that does not report it
            // is treated as enabled, matching how the resolver reads it.
            if let offender = matched.first(where: { ($0.enabled ?? true) != enabled }) {
                return "expected enabled=\(enabled), found enabled=\(offender.enabled ?? true)"
            }
        }
        if let valueEquals {
            if let offender = matched.first(where: { AXNode.trimmed($0.AXValue) != valueEquals }) {
                return "expected value \"\(valueEquals)\", found \"\(AXNode.trimmed(offender.AXValue) ?? "")\""
            }
        }
        if let valueMatches {
            guard let regex = try? NSRegularExpression(pattern: valueMatches) else {
                return "value-matches pattern is not a valid regular expression: \(valueMatches)"
            }
            if let offender = matched.first(where: { !regex.matchesAnywhere(AXNode.trimmed($0.AXValue) ?? "") }) {
                return "expected value matching /\(valueMatches)/, found \"\(AXNode.trimmed(offender.AXValue) ?? "")\""
            }
        }
        if let minWidth {
            if let offender = matched.first(where: { ($0.frame?.width ?? 0) < minWidth }) {
                return String(format: "expected width >= %.0fpt, found %.0fpt", minWidth, offender.frame?.width ?? 0)
            }
        }
        if let minHeight {
            if let offender = matched.first(where: { ($0.frame?.height ?? 0) < minHeight }) {
                return String(format: "expected height >= %.0fpt, found %.0fpt", minHeight, offender.frame?.height ?? 0)
            }
        }
        return nil
    }

    /// Elements matching the selector. Selector fields are ANDed; string
    /// comparisons are exact after trimming, matching how the tap resolver reads
    /// labels. Use `contains` for substring matching.
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

extension NSRegularExpression {
    /// Whether the pattern matches anywhere in `text`. Used for the `matches` /
    /// `value-matches` verify forms, which are search semantics (like grep), not
    /// full-string anchoring — a caller who wants anchoring writes `^...$`.
    ///
    /// Named for what it does: an earlier `matchesWhole` read as full-string
    /// matching and invited exactly the wrong assumption at every call site.
    func matchesAnywhere(_ text: String) -> Bool {
        firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
