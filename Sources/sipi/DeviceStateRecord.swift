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

    /// Read the three simctl-exposed appearance facets. Each read is independent:
    /// one failing does not hide the other two, and a failure becomes a warning
    /// rather than an error because evidence must never abort the run it
    /// describes.
    static func capture(
        appearance: () throws -> String,
        contentSize: () throws -> String,
        increaseContrast: () throws -> String
    ) -> Outcome {
        var outcome = Outcome(state: [:], warnings: [])
        func record(_ facet: String, _ read: () throws -> String) {
            do {
                let value = try read().trimmingCharacters(in: .whitespacesAndNewlines)
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
        return outcome
    }
}
