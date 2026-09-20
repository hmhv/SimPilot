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

    // MARK: - Fold state

    /// Which screen a foldable is showing decides what every screenshot in the
    /// run is OF, and nothing in the run can set it — so it is recorded next to
    /// the appearance facets.
    func testFoldPoseIsRecordedForAFoldable() {
        let outcome = DeviceStateRecord.capture(
            appearance: { "light" },
            contentSize: { "medium" },
            increaseContrast: { "disabled" },
            foldState: { "folded (cover 466x678pt)" }
        )
        XCTAssertEqual(outcome.state["fold-state"], "folded (cover 466x678pt)")
        XCTAssertEqual(outcome.warnings, [])
    }

    /// Almost every device has one screen and therefore no pose. That is not a
    /// failed read: no facet, and no warning either.
    func testADeviceThatCannotFoldRecordsNoFacetAndNoWarning() {
        let outcome = DeviceStateRecord.capture(
            appearance: { "light" },
            contentSize: { "medium" },
            increaseContrast: { "disabled" },
            foldState: { nil }
        )
        XCTAssertNil(outcome.state["fold-state"])
        XCTAssertEqual(outcome.warnings, [])
        XCTAssertEqual(outcome.state.count, 3)
    }

    /// Callers written before the facet existed keep working, and keep recording
    /// exactly the three facets they always did.
    func testOmittingTheFoldReadIsTheSameAsHavingNone() {
        let outcome = DeviceStateRecord.capture(
            appearance: { "dark" },
            contentSize: { "large" },
            increaseContrast: { "enabled" }
        )
        XCTAssertEqual(outcome.state, [
            "appearance": "dark",
            "content-size": "large",
            "increase-contrast": "enabled"
        ])
    }

    func testAFailedFoldReadWarnsWithoutHidingTheOtherFacets() {
        let outcome = DeviceStateRecord.capture(
            appearance: { "light" },
            contentSize: { "medium" },
            increaseContrast: { "disabled" },
            foldState: { throw ReadFailed() }
        )
        XCTAssertEqual(outcome.state.count, 3)
        XCTAssertEqual(outcome.warnings.count, 1)
        XCTAssertTrue(outcome.warnings[0].contains("fold-state"))
    }
}
