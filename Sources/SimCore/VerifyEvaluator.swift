// VerifyEvaluator.swift
//
// Pure evaluation of `wait-for` conditions against an accessibility-tree
// capture, kept apart from the command so the correctness rules below are
// unit-testable without a live simulator.
//
// Two condition forms:
//   contains / absent          substring over the serialized tree
//   elements                   an element exists or is gone (see ElementCondition)
//
// Correctness rules (why this is not a one-liner):
//   - Absence is only trustworthy against the DEEPEST tree. A string is truly
//     absent only if it is missing from the deep tree (which also carries System
//     UI and the grid pass). Evaluating absence against the fast tree alone can
//     PASS while the forbidden string is actually on screen — a false PASS. So
//     whenever any absence-shaped condition is present (`absent`, or an element
//     condition asserting non-existence), the deep tree is fetched
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

    /// Evaluate every condition against `fast`, escalating to `deep` when
    /// needed. `deep` is called at most once.
    public static func evaluate(
        contains: [String] = [],
        absent: [String] = [],
        elements: [ElementCondition] = [],
        fast: Capture,
        deep: () throws -> Capture
    ) rethrows -> [Row] {
        let needDeep = requiresDeep(contains: contains, absent: absent, elements: elements, fast: fast)
        let tree = needDeep ? try deep() : fast

        var rows: [Row] = []
        for text in contains {
            let found = tree.json.contains(AXNodeJSON.escaped(text))
            rows.append(Row(check: "contains: \(text)", found: found, grepMatch: found ? text : nil))
        }
        for text in absent {
            // `tree` is the deep capture here: `needDeep` is true whenever any
            // absence-shaped condition exists.
            let present = tree.json.contains(AXNodeJSON.escaped(text))
            rows.append(Row(check: "absent: \(text)", found: !present, grepMatch: present ? text : "absent"))
        }
        for condition in elements {
            let reason = condition.failureReason(in: tree.nodes)
            rows.append(Row(
                check: "element: \(condition.selectorDescription) [\(condition.assertsAbsence ? "absent" : "exists")]",
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
        elements: [ElementCondition],
        fast: Capture
    ) -> Bool {
        // Absence-shaped conditions always need the deep tree.
        if !absent.isEmpty { return true }
        if elements.contains(where: \.assertsAbsence) { return true }
        // Presence-shaped conditions escalate only when the fast tree misses them.
        if contains.contains(where: { !fast.json.contains(AXNodeJSON.escaped($0)) }) { return true }
        if elements.contains(where: { $0.failureReason(in: fast.nodes) != nil }) { return true }
        return false
    }
}
