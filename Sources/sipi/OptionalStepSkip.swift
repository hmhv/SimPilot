// OptionalStepSkip.swift
//
// The rule that decides whether an `optional` test step may be recorded as a
// passing skip.
//
// It lives apart from HarnessRunner, and takes the tree probe as a closure, so
// the decision can be tested without a simulator: the runner owns the driver,
// this owns the judgment.

import Foundation

enum OptionalStepSkip {

    /// Action types whose target is pre-resolved, and which an `optional` step
    /// may therefore skip.
    ///
    /// Deliberately narrow. `set-text` is targeted the same way a `tap` is and
    /// could in principle be pre-resolved, but it is excluded: writing a value is
    /// not an interaction a test can silently do without, so a missing field
    /// should fail loudly rather than turn into a green skip. `type`, `swipe`,
    /// `gesture`, and the simulator controls have no selector at all.
    static let skippableActionTypes: Set<String> = ["tap", "double-tap", "long-press", "slider"]

    /// Whether the target is DEFINITIVELY absent, given a probe that answers
    /// "does this tree contain it?" for the fast tree (`deep: false`) and then
    /// the deep one.
    ///
    /// Absent means the probe returned false for BOTH trees. A probe that throws
    /// means "could not tell" — an ambiguous selector, an unreadable
    /// accessibility tree — and that is NOT an absent target: returning true
    /// there would record a real defect as `passed: true, skipped: true` and
    /// hide it behind a green step.
    ///
    /// So a throw does not skip; it falls through to normal execution, which
    /// decides the outcome. That is deliberately weaker than "it fails": a
    /// transient tree read failure can still pass on the step's own attempt,
    /// while a genuinely ambiguous selector fails there with its real error.
    static func targetIsDefinitelyAbsent(probe: (_ deep: Bool) throws -> Bool) -> Bool {
        do {
            // Missing from the fast tree only means "look deeper".
            guard try !probe(false) else { return false }
            return try !probe(true)
        } catch {
            return false
        }
    }
}
