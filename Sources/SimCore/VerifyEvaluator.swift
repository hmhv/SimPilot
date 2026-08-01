// VerifyEvaluator.swift
//
// Pure evaluation of verify conditions against an accessibility-tree capture.
// Extracted from the harness so the correctness rules below are unit-testable
// without a live simulator.
//
// Five condition forms, in increasing precision:
//   contains / absent          substring over the serialized tree
//   matches / not-matches      regular expression over the serialized tree
//   elements                   structured assertions over the node tree
//     (see ElementCondition — enabled state, exact value, counts, touch targets)
//
// Correctness rules (why this is not a one-liner):
//   - Absence is only trustworthy against the DEEPEST tree. A string is truly
//     absent only if it is missing from the deep tree (which also carries System
//     UI and the grid pass). Evaluating absence against the fast tree alone can
//     PASS while the forbidden string is actually on screen — a false PASS. So
//     whenever any absence-shaped condition is present (`absent`, `not-matches`,
//     or an element condition asserting non-existence), the deep tree is fetched
//     and used for everything.
//   - Presence-shaped conditions escalate to the deep tree only when the fast
//     tree does not already satisfy them (a present-in-deep-only match must
//     still match).
//   - The deep capture is fetched at most once, and only when deep is needed.

import Foundation

public enum VerifyEvaluator {
    /// One evaluated verify condition.
    public struct Row: Equatable {
        public let check: String
        public let found: Bool
        /// The matched text, or the reason the check failed; `nil` serializes to
        /// JSON null.
        public let grepMatch: String?

        public init(check: String, found: Bool, grepMatch: String?) {
            self.check = check
            self.found = found
            self.grepMatch = grepMatch
        }
    }

    /// One accessibility-tree capture in both the forms the conditions need: the
    /// serialized text for the grep-shaped checks, and the parsed nodes for the
    /// structured ones.
    public struct Capture {
        public let json: String
        public let nodes: [AXNode]

        public init(json: String, nodes: [AXNode] = []) {
            self.json = json
            self.nodes = nodes
        }
    }

    /// Evaluate `contains` / `absent` only. Retained for callers that never use
    /// the structured forms; delegates to the full evaluator.
    public static func evaluate(
        contains: [String],
        absent: [String],
        fastJSON: String,
        deepJSON: () throws -> String
    ) rethrows -> [Row] {
        try evaluate(
            contains: contains,
            absent: absent,
            fast: Capture(json: fastJSON),
            deep: { Capture(json: try deepJSON()) }
        )
    }

    /// Evaluate every verify form against `fast`, escalating to `deep` when
    /// needed. `deep` is called at most once.
    public static func evaluate(
        contains: [String] = [],
        absent: [String] = [],
        matches: [String] = [],
        notMatches: [String] = [],
        elements: [ElementCondition] = [],
        fast: Capture,
        deep: () throws -> Capture
    ) rethrows -> [Row] {
        let needDeep = requiresDeep(
            contains: contains,
            absent: absent,
            matches: matches,
            notMatches: notMatches,
            elements: elements,
            fast: fast
        )
        let tree = needDeep ? try deep() : fast

        var rows: [Row] = []
        for text in contains {
            let found = tree.json.contains(text)
            rows.append(Row(check: "contains: \(text)", found: found, grepMatch: found ? text : nil))
        }
        for text in absent {
            // `tree` is the deep capture here: `needDeep` is true whenever any
            // absence-shaped condition exists.
            let present = tree.json.contains(text)
            rows.append(Row(check: "absent: \(text)", found: !present, grepMatch: present ? text : "absent"))
        }
        for pattern in matches {
            rows.append(regexRow(pattern: pattern, in: tree.json, expectMatch: true))
        }
        for pattern in notMatches {
            rows.append(regexRow(pattern: pattern, in: tree.json, expectMatch: false))
        }
        for condition in elements {
            let reason = condition.failureReason(in: tree.nodes)
            rows.append(Row(
                check: "element: \(condition.selectorDescription) [\(condition.assertionDescription)]",
                found: reason == nil,
                grepMatch: reason ?? "ok"
            ))
        }
        return rows
    }

    /// Whether the deep tree must be fetched before any condition can be trusted.
    private static func requiresDeep(
        contains: [String],
        absent: [String],
        matches: [String],
        notMatches: [String],
        elements: [ElementCondition],
        fast: Capture
    ) -> Bool {
        // Absence-shaped conditions always need the deep tree.
        if !absent.isEmpty || !notMatches.isEmpty { return true }
        if elements.contains(where: \.assertsAbsence) { return true }
        // Presence-shaped conditions escalate only when the fast tree misses them.
        if contains.contains(where: { !fast.json.contains($0) }) { return true }
        if matches.contains(where: { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                // An invalid pattern fails either way; do not pay for a deep pass.
                return false
            }
            return !regex.matchesAnywhere(fast.json)
        }) { return true }
        if elements.contains(where: { $0.failureReason(in: fast.nodes) != nil }) { return true }
        return false
    }

    private static func regexRow(pattern: String, in json: String, expectMatch: Bool) -> Row {
        let label = expectMatch ? "matches" : "not-matches"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return Row(
                check: "\(label): \(pattern)",
                found: false,
                grepMatch: "invalid regular expression"
            )
        }
        let matched = regex.matchesAnywhere(json)
        return Row(
            check: "\(label): \(pattern)",
            found: matched == expectMatch,
            grepMatch: matched ? pattern : (expectMatch ? nil : "absent")
        )
    }
}
