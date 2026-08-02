// StepNoteTests.swift
//
// Locks what a step result's `note` tells the reader.
//
// The regression this guards: the action error used to be held across the whole
// step rather than per attempt, so a step whose first attempt threw and whose
// second reached verify and failed there reported `failure-type: verify` next to
// the first attempt's ACTION error — a cause that had nothing to do with how the
// step ended. The loop now clears it per attempt; these tests pin the
// composition rules it feeds.

import XCTest
@testable import sipi

final class StepNoteTests: XCTestCase {

    // MARK: - Precedence

    func testSuppressedRetryReasonWinsThePrimarySlot() {
        let note = StepNote.compose(
            retryUnsafeNote: "text was sent but could not be read back",
            stepNote: "author's note",
            lastActionError: "some resolver error",
            artifactErrors: [],
            passed: false
        )
        XCTAssertEqual(note, "text was sent but could not be read back",
                       "it explains the failure AND why no retry followed")
    }

    func testAuthorNoteIsUsedWhenThereIsNoSuppressedRetry() {
        let note = StepNote.compose(
            retryUnsafeNote: nil, stepNote: "author's note",
            lastActionError: nil, artifactErrors: [], passed: true
        )
        XCTAssertEqual(note, "author's note")
    }

    func testFailedStepAppendsTheUnderlyingErrorWithoutDroppingTheAuthorNote() {
        let note = StepNote.compose(
            retryUnsafeNote: nil, stepNote: "author's note",
            lastActionError: "Multiple (3) accessibility elements matched label 'Delete'",
            artifactErrors: [], passed: false
        )
        XCTAssertEqual(
            note,
            "author's note | Multiple (3) accessibility elements matched label 'Delete'"
        )
    }

    func testPassedStepDoesNotCarryAnActionError() {
        let note = StepNote.compose(
            retryUnsafeNote: nil, stepNote: nil,
            lastActionError: "an error from an earlier attempt that later succeeded",
            artifactErrors: [], passed: true
        )
        XCTAssertEqual(note, "", "a step that ended green owes no failure cause")
    }

    func testArtifactErrorsComeLast() {
        let note = StepNote.compose(
            retryUnsafeNote: nil, stepNote: nil,
            lastActionError: "resolver error",
            artifactErrors: ["screenshot capture failed"],
            passed: false
        )
        XCTAssertEqual(note, "resolver error | screenshot capture failed")
    }

    func testNothingToSayYieldsAnEmptyNote() {
        XCTAssertEqual(
            StepNote.compose(retryUnsafeNote: nil, stepNote: nil, lastActionError: nil,
                             artifactErrors: [], passed: true),
            ""
        )
    }

    // MARK: - Verify mismatch summary

    func testVerifyMismatchSummaryNamesOnlyTheUnmetChecks() {
        let rows: [[String: Any]] = [
            ["check": "contains: Dashboard", "found": false],
            ["check": "absent: Sign In", "found": true],
            ["check": "contains: Welcome", "found": false]
        ]
        XCTAssertEqual(
            StepNote.verifyMismatchSummary(rows),
            "verify not satisfied — contains: Dashboard, contains: Welcome"
        )
    }

    func testVerifyMismatchSummaryFallsBackWhenNoRowIsIdentifiable() {
        XCTAssertEqual(StepNote.verifyMismatchSummary([]), "verify not satisfied")
    }
}
