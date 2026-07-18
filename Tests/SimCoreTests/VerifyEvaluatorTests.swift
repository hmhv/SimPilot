// VerifyEvaluatorTests.swift
//
// Locks the verify-evaluation correctness rules that used to live (buggy) inside
// the harness: `absent` must be judged against the deep tree, `contains` must
// escalate to deep on demand, and the deep tree must not be fetched needlessly.

import XCTest
@testable import SimCore

final class VerifyEvaluatorTests: XCTestCase {

    /// Regression for the false-PASS bug: a forbidden `absent` string that is
    /// present only in the deep tree (e.g. a System-UI dialog) must be detected,
    /// not passed off the fast tree.
    func testAbsentStringOnlyInDeepTreeIsDetected() {
        let fast = "{app: Home, Settings}"
        let deep = fast + " {system-ui: Error dialog}"
        let rows = VerifyEvaluator.evaluate(
            contains: ["Home"], absent: ["Error dialog"], fastJSON: fast, deepJSON: { deep }
        )
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows[0].found, "contains 'Home' should be found")
        XCTAssertFalse(rows[1].found, "'Error dialog' present in deep tree must fail the absent check")
        XCTAssertEqual(rows[1].grepMatch, "Error dialog")
    }

    func testAbsentStringTrulyGoneReportsAbsent() {
        let rows = VerifyEvaluator.evaluate(
            contains: [], absent: ["Error"], fastJSON: "Home Settings", deepJSON: { "Home Settings" }
        )
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].found)
        XCTAssertEqual(rows[0].grepMatch, "absent")
    }

    func testContainsEscalatesToDeepTree() {
        let rows = VerifyEvaluator.evaluate(
            contains: ["Dashboard"], absent: [], fastJSON: "Home", deepJSON: { "Home Dashboard" }
        )
        XCTAssertTrue(rows[0].found)
        XCTAssertEqual(rows[0].grepMatch, "Dashboard")
    }

    func testDeepTreeNotFetchedWhenFastSatisfiesAndNoAbsent() {
        var deepCalls = 0
        let rows = VerifyEvaluator.evaluate(
            contains: ["Home", "Dashboard"], absent: [], fastJSON: "Home Dashboard",
            deepJSON: { deepCalls += 1; return "unused" }
        )
        XCTAssertEqual(deepCalls, 0, "deep tree must not be fetched when it is not needed")
        XCTAssertTrue(rows.allSatisfy { $0.found })
    }

    func testDeepTreeFetchedWhenAbsentPresentEvenIfContainsInFast() {
        var deepCalls = 0
        _ = VerifyEvaluator.evaluate(
            contains: ["Home"], absent: ["X"], fastJSON: "Home",
            deepJSON: { deepCalls += 1; return "Home" }
        )
        XCTAssertEqual(deepCalls, 1, "any absent condition must force a deep fetch")
    }

    func testContainsNotFoundHasNilGrepMatch() {
        let rows = VerifyEvaluator.evaluate(
            contains: ["Missing"], absent: [], fastJSON: "Home", deepJSON: { "Home" }
        )
        XCTAssertFalse(rows[0].found)
        XCTAssertNil(rows[0].grepMatch)
    }
}
