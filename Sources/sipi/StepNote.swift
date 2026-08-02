// StepNote.swift
//
// How a step result's `note` field is assembled, and how a verify mismatch is
// summarised for the trace.
//
// Split out of HarnessRunner so the precedence rules are testable without a
// simulator: the runner owns the attempt loop, this owns what the reader is
// told about how the step ended.

import Foundation

enum StepNote {

    /// Build the `note` value, or "" when there is nothing to say.
    ///
    /// Precedence for the primary slot:
    ///
    /// 1. A suppressed-retry reason. It explains the failure AND why no retry
    ///    followed, which no other note can.
    /// 2. Otherwise the spec's own `note`, which is the author talking to the
    ///    reader.
    ///
    /// A failed step then appends the underlying error, because `failure-type`
    /// names a category (`action` / `verify`) and not a cause — without it a
    /// resolver complaint like "Multiple (3) accessibility elements matched
    /// label 'Delete'" never reaches the result. It is appended rather than
    /// substituted so an author's note is never dropped.
    ///
    /// Artifact failures come last: they are about the evidence, not the verdict.
    static func compose(
        retryUnsafeNote: String?,
        stepNote: String?,
        lastActionError: String?,
        artifactErrors: [String],
        passed: Bool
    ) -> String {
        var notes = [retryUnsafeNote ?? stepNote].compactMap { $0 }
        if !passed, retryUnsafeNote == nil, let lastActionError {
            notes.append(lastActionError)
        }
        notes += artifactErrors
        return notes.joined(separator: " | ")
    }

    /// One line naming the verify conditions that did not hold, for the trace.
    ///
    /// A mismatch never throws, so without this the trace would show retries with
    /// no reason attached. Rows are the `verifyRowDict` shape: `check` already
    /// reads as `"contains: Dashboard"`, so it needs no further formatting.
    static func verifyMismatchSummary(_ rows: [[String: Any]]) -> String {
        let unmet = rows
            .filter { $0["found"] as? Bool != true }
            .compactMap { $0["check"] as? String }
        return unmet.isEmpty
            ? "verify not satisfied"
            : "verify not satisfied — " + unmet.joined(separator: ", ")
    }
}
