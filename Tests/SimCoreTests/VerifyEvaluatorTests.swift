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

    // MARK: - regex conditions

    func testMatchesCondition() {
        let rows = VerifyEvaluator.evaluate(
            matches: ["Total: \\d+ items"],
            fast: .init(json: "{label: Total: 42 items}"),
            deep: { .init(json: "unused") }
        )
        XCTAssertTrue(rows[0].found)
    }

    func testMatchesEscalatesToDeepTree() {
        var deepCalls = 0
        let rows = VerifyEvaluator.evaluate(
            matches: ["Dash\\w+"],
            fast: .init(json: "Home"),
            deep: { deepCalls += 1; return .init(json: "Home Dashboard") }
        )
        XCTAssertTrue(rows[0].found)
        XCTAssertEqual(deepCalls, 1)
    }

    /// Absence via regex has the same false-PASS hazard as `absent`: it must be
    /// judged against the deep tree.
    func testNotMatchesForcesDeepFetch() {
        var deepCalls = 0
        let rows = VerifyEvaluator.evaluate(
            notMatches: ["Error \\d+"],
            fast: .init(json: "Home"),
            deep: { deepCalls += 1; return .init(json: "Home Error 500") }
        )
        XCTAssertEqual(deepCalls, 1, "not-matches must force a deep fetch")
        XCTAssertFalse(rows[0].found, "a pattern present only in the deep tree must fail not-matches")
    }

    func testInvalidRegexFailsInsteadOfPassing() {
        let rows = VerifyEvaluator.evaluate(
            matches: ["[unclosed"],
            fast: .init(json: "anything"),
            deep: { .init(json: "anything") }
        )
        XCTAssertFalse(rows[0].found)
        XCTAssertEqual(rows[0].grepMatch, "invalid regular expression")
    }

    // MARK: - element conditions

    private func tree(_ nodes: [AXNode]) -> VerifyEvaluator.Capture {
        VerifyEvaluator.Capture(json: (try? AXNodeJSON.string(for: nodes)) ?? "", nodes: nodes)
    }

    private func button(_ label: String, enabled: Bool = true) -> AXNode {
        AXNode(AXLabel: label, role: "AXButton", type: "Button", enabled: enabled,
               frame: AXNode.Frame(x: 0, y: 0, width: 80, height: 44))
    }

    func testElementConditionEvaluatesAgainstNodes() {
        let rows = VerifyEvaluator.evaluate(
            elements: [ElementCondition(label: "Sign In", enabled: true)],
            fast: tree([button("Sign In")]),
            deep: { self.tree([]) }
        )
        XCTAssertTrue(rows[0].found)
        XCTAssertTrue(rows[0].check.contains("label=Sign In"))
    }

    func testFailingElementConditionCarriesTheObservedValue() {
        let rows = VerifyEvaluator.evaluate(
            elements: [ElementCondition(label: "Sign In", enabled: true)],
            fast: tree([button("Sign In", enabled: false)]),
            deep: { self.tree([self.button("Sign In", enabled: false)]) }
        )
        XCTAssertFalse(rows[0].found)
        XCTAssertEqual(rows[0].grepMatch, "expected enabled=true, found enabled=false")
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
            matches: ["Ho\\w+"],
            elements: [ElementCondition(label: "Home")],
            fast: tree([button("Home")]),
            deep: { deepCalls += 1; return self.tree([self.button("Home")]) }
        )
        XCTAssertEqual(deepCalls, 1, "the deep capture must be fetched at most once")
        XCTAssertEqual(rows.count, 4)
        XCTAssertTrue(rows.allSatisfy { $0.found }, "\(rows)")
    }
}
