// DeviceStateRecord.swift
//
// The simulator's appearance state at the moment a run starts, recorded into
// `run.json` as evidence.
//
// Why it exists: the harness restores appearance, Dynamic Type and Increase
// Contrast to the value it read right before its first write, so whatever the
// device already had becomes the baseline. A run killed mid-way (Ctrl-C, a CI
// timeout) skips that restore, and the leftover — dark mode, an accessibility
// text size — is then inherited by every later run as its "baseline" without
// anything saying so. Recording the state up front lets a reader explain a
// screenshot that looks wrong for reasons no step in the spec caused.
//
// It records; it never judges. Whether dark mode at run start is a leftover or
// the intended condition is not something the harness can know.
//
// Split out of HarnessRunner so the shape of the record — which facets, how a
// failed read is reported — is testable without a simulator.

import Foundation

enum DeviceStateRecord {

    /// The record and the warnings a reader should see next to it.
    struct Outcome: Equatable {
        /// Facet name → value as `simctl ui` reports it (`dark`,
        /// `accessibility-extra-large`, `enabled` …). A facet whose read failed is
        /// absent rather than carrying a placeholder.
        var state: [String: String]
        /// One line per failed read, naming the facet, for `evidence-warnings`.
        var warnings: [String]
    }

    /// Read the appearance facets, plus the fold pose on a device that has one.
    /// Each read is independent: one failing does not hide the others, and a
    /// failure becomes a warning rather than an error because evidence must
    /// never abort the run it describes.
    ///
    /// `foldState` returns nil for a device with one screen — the overwhelming
    /// majority — and that is not a failed read: there is no pose, so no facet
    /// is recorded and no warning is raised.
    static func capture(
        appearance: () throws -> String,
        contentSize: () throws -> String,
        increaseContrast: () throws -> String,
        foldState: () throws -> String? = { nil }
    ) -> Outcome {
        var outcome = Outcome(state: [:], warnings: [])
        func record(_ facet: String, _ read: () throws -> String?) {
            do {
                guard let raw = try read() else { return }
                let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else {
                    outcome.warnings.append("device state at run start: \(facet) read back empty")
                    return
                }
                outcome.state[facet] = value
            } catch {
                outcome.warnings.append("device state at run start: \(facet) could not be read: \(error)")
            }
        }
        record("appearance", appearance)
        record("content-size", contentSize)
        record("increase-contrast", increaseContrast)
        // Which screen a foldable is showing decides what every screenshot and
        // accessibility tree in this run is OF. Nothing in the run can set it,
        // and nobody watching the results can tell a shut device from a layout
        // that came out the wrong size — unless it is written down here.
        record("fold-state", foldState)
        return outcome
    }
}
