// VerifyEvaluatorTests.swift
//
// Locks the evaluation correctness rules: `absent` must be judged against the
// deep tree, `contains` must escalate to deep on demand, and the deep tree must
// not be fetched needlessly.

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
            contains: ["Home"], absent: ["Error dialog"], fast: .init(json: fast), deep: { .init(json: deep) }
        )
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows[0].found, "contains 'Home' should be found")
        XCTAssertFalse(rows[1].found, "'Error dialog' present in deep tree must fail the absent check")
        XCTAssertEqual(rows[1].grepMatch, "Error dialog")
    }

    func testAbsentStringTrulyGoneReportsAbsent() {
        let rows = VerifyEvaluator.evaluate(
            contains: [], absent: ["Error"], fast: .init(json: "Home Settings"), deep: { .init(json: "Home Settings") }
        )
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].found)
        XCTAssertEqual(rows[0].grepMatch, "absent")
    }

    func testContainsEscalatesToDeepTree() {
        let rows = VerifyEvaluator.evaluate(
            contains: ["Dashboard"], absent: [], fast: .init(json: "Home"), deep: { .init(json: "Home Dashboard") }
        )
        XCTAssertTrue(rows[0].found)
        XCTAssertEqual(rows[0].grepMatch, "Dashboard")
    }

    func testDeepTreeNotFetchedWhenFastSatisfiesAndNoAbsent() {
        var deepCalls = 0
        let rows = VerifyEvaluator.evaluate(
            contains: ["Home", "Dashboard"], absent: [], fast: .init(json: "Home Dashboard"),
            deep: { deepCalls += 1; return .init(json: "unused") }
        )
        XCTAssertEqual(deepCalls, 0, "deep tree must not be fetched when it is not needed")
        XCTAssertTrue(rows.allSatisfy { $0.found })
    }

    func testDeepTreeFetchedWhenAbsentPresentEvenIfContainsInFast() {
        var deepCalls = 0
        _ = VerifyEvaluator.evaluate(
            contains: ["Home"], absent: ["X"], fast: .init(json: "Home"),
            deep: { deepCalls += 1; return .init(json: "Home") }
        )
        XCTAssertEqual(deepCalls, 1, "any absent condition must force a deep fetch")
    }

    func testContainsNotFoundHasNilGrepMatch() {
        let rows = VerifyEvaluator.evaluate(
            contains: ["Missing"], absent: [], fast: .init(json: "Home"), deep: { .init(json: "Home") }
        )
        XCTAssertFalse(rows[0].found)
        XCTAssertNil(rows[0].grepMatch)
    }

    // MARK: - element conditions

    private func tree(_ nodes: [AXNode]) -> VerifyEvaluator.Capture {
        VerifyEvaluator.Capture(json: (try? AXNodeJSON.string(for: nodes)) ?? "", nodes: nodes)
    }

    private func button(_ label: String) -> AXNode {
        AXNode(AXLabel: label, role: "AXButton", type: "Button", enabled: true,
               frame: AXNode.Frame(x: 0, y: 0, width: 80, height: 44))
    }

    func testElementConditionEvaluatesAgainstNodes() {
        let rows = VerifyEvaluator.evaluate(
            elements: [ElementCondition(label: "Sign In")],
            fast: tree([button("Sign In")]),
            deep: { self.tree([]) }
        )
        XCTAssertTrue(rows[0].found)
        XCTAssertTrue(rows[0].check.contains("label=Sign In"))
    }

    func testElementConditionEscalatesToDeepTree() {
        var deepCalls = 0
        let rows = VerifyEvaluator.evaluate(
            elements: [ElementCondition(label: "Alert")],
            fast: tree([button("Home")]),
            deep: { deepCalls += 1; return self.tree([self.button("Alert")]) }
        )
        XCTAssertEqual(deepCalls, 1)
        XCTAssertTrue(rows[0].found)
    }

    /// An element condition asserting non-existence is absence-shaped, so it must
    /// force the deep fetch just like `absent`.
    func testAbsenceElementConditionForcesDeepFetch() {
        var deepCalls = 0
        let rows = VerifyEvaluator.evaluate(
            elements: [ElementCondition(label: "Alert", exists: false)],
            fast: tree([button("Home")]),
            deep: { deepCalls += 1; return self.tree([self.button("Alert")]) }
        )
        XCTAssertEqual(deepCalls, 1, "exists=false must force a deep fetch")
        XCTAssertFalse(rows[0].found, "an element present only in the deep tree must fail exists=false")
    }

    func testMixedConditionsShareOneDeepFetch() {
        var deepCalls = 0
        let rows = VerifyEvaluator.evaluate(
            contains: ["Home"],
            absent: ["Error"],
            elements: [ElementCondition(label: "Home")],
            fast: tree([button("Home")]),
            deep: { deepCalls += 1; return self.tree([self.button("Home")]) }
        )
        XCTAssertEqual(deepCalls, 1, "the deep capture must be fetched at most once")
        XCTAssertEqual(rows.count, 3)
        XCTAssertTrue(rows.allSatisfy { $0.found }, "\(rows)")
    }
}
