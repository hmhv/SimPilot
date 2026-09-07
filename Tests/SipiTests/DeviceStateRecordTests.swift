// DeviceStateRecordTests.swift
//
// Locks the shape of the run-start device-state record in `run.json`.
//
// The situation it exists for: a run killed before its cleanup leaves the
// simulator in dark mode or at an accessibility text size, and the next run
// silently adopts that as its baseline. The record is the only place a reader
// can see it, so a failed read must be visible as a warning and must not hide
// the facets that did read.

import XCTest
@testable import sipi

final class DeviceStateRecordTests: XCTestCase {

    private struct ReadFailed: Error, CustomStringConvertible {
        var description: String { "simctl exited 1" }
    }

    func testAllThreeFacetsAreRecordedAsReported() {
        let outcome = DeviceStateRecord.capture(
            appearance: { "dark\n" },
            contentSize: { "accessibility-extra-large" },
            increaseContrast: { "enabled" }
        )
        XCTAssertEqual(outcome.state, [
            "appearance": "dark",
            "content-size": "accessibility-extra-large",
            "increase-contrast": "enabled"
        ], "values are passed through as simctl reports them, trimmed only")
        XCTAssertEqual(outcome.warnings, [])
    }

    func testAFailedReadBecomesAWarningAndDoesNotHideTheOthers() {
        let outcome = DeviceStateRecord.capture(
            appearance: { "light" },
            contentSize: { throw ReadFailed() },
            increaseContrast: { "unsupported" }
        )
        XCTAssertEqual(outcome.state, [
            "appearance": "light",
            "increase-contrast": "unsupported"
        ], "the failed facet is absent, not a placeholder")
        XCTAssertEqual(outcome.warnings.count, 1)
        XCTAssertTrue(outcome.warnings[0].contains("content-size"), "the warning names the facet")
        XCTAssertTrue(outcome.warnings[0].contains("simctl exited 1"), "and carries the underlying error")
    }

    func testAnEmptyReadIsAWarningNotAnEmptyValue() {
        let outcome = DeviceStateRecord.capture(
            appearance: { "  \n" },
            contentSize: { "medium" },
            increaseContrast: { "disabled" }
        )
        XCTAssertNil(outcome.state["appearance"])
        XCTAssertEqual(outcome.warnings, ["device state at run start: appearance read back empty"])
    }

    func testEveryReadFailingLeavesAnEmptyRecordAndThreeWarnings() {
        let outcome = DeviceStateRecord.capture(
            appearance: { throw ReadFailed() },
            contentSize: { throw ReadFailed() },
            increaseContrast: { throw ReadFailed() }
        )
        XCTAssertEqual(outcome.state, [:], "nothing is invented when nothing could be read")
        XCTAssertEqual(outcome.warnings.count, 3)
    }
}
