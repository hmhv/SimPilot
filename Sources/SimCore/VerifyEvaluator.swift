// VerifyEvaluator.swift
//
// Pure evaluation of `contains` / `absent` verify conditions against the
// accessibility-tree JSON. Extracted from the harness so the correctness rules
// below are unit-testable without a live simulator.
//
// Correctness rules (why this is not a one-liner):
//   - `absent` is only trustworthy against the DEEPEST tree. A string is truly
//     absent only if it is missing from the deep tree (which also carries System
//     UI and the grid pass). Evaluating `absent` against the fast tree alone can
//     PASS while the forbidden string is actually on screen — a false PASS. So
//     whenever there is any `absent` condition, the deep tree is fetched and used.
//   - `contains` escalates to the deep tree only when an expected string is
//     missing from the fast tree (a present-in-deep-only string must still match).
//   - `deepJSON` is invoked at most once, and only when deep is actually needed.

import Foundation

public enum VerifyEvaluator {
    /// One evaluated verify condition.
    public struct Row: Equatable {
        public let check: String
        public let found: Bool
        /// The matched (or offending) text; `nil` serializes to JSON null.
        public let grepMatch: String?

        public init(check: String, found: Bool, grepMatch: String?) {
            self.check = check
            self.found = found
            self.grepMatch = grepMatch
        }
    }

    /// Evaluate the verify conditions. `fastJSON` is the fast-tree capture;
    /// `deepJSON` lazily provides the deep-tree capture and is called at most once.
    public static func evaluate(
        contains: [String],
        absent: [String],
        fastJSON: String,
        deepJSON: () throws -> String
    ) rethrows -> [Row] {
        // Deep is required if any `absent` condition exists (absence must be
        // proven against the deep tree), or if a `contains` string is not yet
        // satisfied by the fast tree.
        let needDeep = !absent.isEmpty || contains.contains { !fastJSON.contains($0) }
        let tree = needDeep ? try deepJSON() : fastJSON

        var rows: [Row] = []
        for text in contains {
            let found = tree.contains(text)
            rows.append(Row(check: "contains: \(text)", found: found, grepMatch: found ? text : nil))
        }
        for text in absent {
            // `tree` is the deep tree here, because `needDeep` is true whenever
            // `absent` is non-empty.
            let present = tree.contains(text)
            rows.append(Row(check: "absent: \(text)", found: !present, grepMatch: present ? text : "absent"))
        }
        return rows
    }
}
