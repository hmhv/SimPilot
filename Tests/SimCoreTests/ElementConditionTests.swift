// ElementConditionTests.swift
//
// Locks the structured verify assertions. The important cases are the ones that
// must NOT pass vacuously: an assertion about a property of an element that does
// not exist has to fail, not succeed over an empty set.

import XCTest
@testable import SimCore

final class ElementConditionTests: XCTestCase {

    private func node(
        label: String? = nil,
        id: String? = nil,
        value: String? = nil,
        type: String = "Button",
        enabled: Bool? = true,
        width: Double = 100,
        height: Double = 44
    ) -> AXNode {
        AXNode(
            AXLabel: label,
            AXValue: value,
            role: "AX" + type,
            type: type,
            AXUniqueId: id,
            enabled: enabled,
            frame: AXNode.Frame(x: 0, y: 0, width: width, height: height)
        )
    }

    private lazy var screen: [AXNode] = [
        AXNode(type: "Window", children: [
            node(label: "Sign In", id: "auth.submit"),
            node(label: "Email", id: "auth.email", value: "user@example.com", type: "TextField"),
            node(label: "Cancel", id: "auth.cancel", enabled: false),
            node(label: "Row", id: "row.1", type: "Cell"),
            node(label: "Row", id: "row.2", type: "Cell"),
            node(label: "Row", id: "row.3", type: "Cell")
        ])
    ]

    // MARK: - existence

    func testBareSelectorMeansExists() {
        XCTAssertNil(ElementCondition(label: "Sign In").failureReason(in: screen))
        XCTAssertNotNil(ElementCondition(label: "Nope").failureReason(in: screen))
    }

    func testExistsFalsePassesWhenGone() {
        XCTAssertNil(ElementCondition(label: "Nope", exists: false).failureReason(in: screen))
        XCTAssertNotNil(ElementCondition(label: "Sign In", exists: false).failureReason(in: screen))
    }

    /// The vacuous-pass guard: asserting a property of a missing element must
    /// fail, never succeed over an empty match set.
    func testPropertyAssertionOnMissingElementFails() {
        let reason = ElementCondition(label: "Nope", enabled: true).failureReason(in: screen)
        XCTAssertEqual(reason, "no element matched")
    }

    // MARK: - enabled

    func testEnabledAssertion() {
        XCTAssertNil(ElementCondition(label: "Sign In", enabled: true).failureReason(in: screen))
        XCTAssertNil(ElementCondition(label: "Cancel", enabled: false).failureReason(in: screen))
        let reason = ElementCondition(label: "Cancel", enabled: true).failureReason(in: screen)
        XCTAssertEqual(reason, "expected enabled=true, found enabled=false")
    }

    /// An element that omits `enabled` is treated as enabled, matching how the tap
    /// resolver reads the tree.
    func testMissingEnabledFieldReadsAsEnabled() {
        let roots = [node(label: "Ghost", enabled: nil)]
        XCTAssertNil(ElementCondition(label: "Ghost", enabled: true).failureReason(in: roots))
    }

    // MARK: - value as a selector

    /// `value` narrows which elements match; `valueEquals` asserts about the ones
    /// that already did. The two are easy to conflate, and only the assertion
    /// form was covered — so a broken `value` selector would have picked the
    /// wrong element on every tap without a single test noticing.
    func testValueSelectsRatherThanAsserts() {
        XCTAssertNil(ElementCondition(value: "user@example.com", count: 1).failureReason(in: screen))
        XCTAssertEqual(
            ElementCondition(value: "nobody@example.com").failureReason(in: screen),
            "no element matched"
        )
    }

    /// The selector is ANDed with the others, so a value that belongs to a
    /// different element must not match.
    func testValueSelectorIsCombinedWithTheOthers() {
        XCTAssertNil(ElementCondition(label: "Email", value: "user@example.com").failureReason(in: screen))
        XCTAssertEqual(
            ElementCondition(label: "Sign In", value: "user@example.com").failureReason(in: screen),
            "no element matched"
        )
    }

    // MARK: - value

    func testValueEquals() {
        XCTAssertNil(ElementCondition(id: "auth.email", valueEquals: "user@example.com").failureReason(in: screen))
        let reason = ElementCondition(id: "auth.email", valueEquals: "other").failureReason(in: screen)
        XCTAssertEqual(reason, "expected value \"other\", found \"user@example.com\"")
    }

    func testValueMatchesUsesSearchSemantics() {
        XCTAssertNil(ElementCondition(id: "auth.email", valueMatches: "@example\\.com$").failureReason(in: screen))
        XCTAssertNil(ElementCondition(id: "auth.email", valueMatches: "example").failureReason(in: screen))
        XCTAssertNotNil(ElementCondition(id: "auth.email", valueMatches: "^admin").failureReason(in: screen))
    }

    func testInvalidRegexIsReportedNotCrashed() {
        let reason = ElementCondition(id: "auth.email", valueMatches: "[unclosed").failureReason(in: screen)
        XCTAssertEqual(reason, "value-matches pattern is not a valid regular expression: [unclosed")
    }

    // MARK: - counts

    func testExactCount() {
        XCTAssertNil(ElementCondition(elementType: "Cell", count: 3).failureReason(in: screen))
        let reason = ElementCondition(elementType: "Cell", count: 2).failureReason(in: screen)
        XCTAssertEqual(reason, "expected 2 matching element(s), found 3")
    }

    func testCountZeroAssertsAbsence() {
        XCTAssertNil(ElementCondition(elementType: "Slider", count: 0).failureReason(in: screen))
        XCTAssertNotNil(ElementCondition(elementType: "Cell", count: 0).failureReason(in: screen))
    }

    func testMinAndMaxCount() {
        XCTAssertNil(ElementCondition(elementType: "Cell", minCount: 2).failureReason(in: screen))
        XCTAssertNil(ElementCondition(elementType: "Cell", maxCount: 5).failureReason(in: screen))
        XCTAssertNotNil(ElementCondition(elementType: "Cell", minCount: 4).failureReason(in: screen))
        XCTAssertNotNil(ElementCondition(elementType: "Cell", maxCount: 2).failureReason(in: screen))
    }

    /// `max-count: 0` is an absence assertion — `assertsAbsence` says so, and
    /// `VerifyEvaluator` forces a deep fetch because of it. Evaluation must agree:
    /// with nothing matching it has to PASS, not fall through to "no element
    /// matched" and fail on exactly the screen it was written to accept.
    func testMaxCountZeroPassesWhenNothingMatches() {
        XCTAssertNil(ElementCondition(elementType: "Slider", maxCount: 0).failureReason(in: screen))
        XCTAssertNil(ElementCondition(label: "Spinner", maxCount: 0).failureReason(in: screen))
    }

    func testMaxCountZeroFailsWhenSomethingMatches() {
        let reason = ElementCondition(elementType: "Cell", maxCount: 0).failureReason(in: screen)
        XCTAssertEqual(reason, "expected no match, found 3")
    }

    /// Every absence form must agree on both the pass and the fail side, so a
    /// spec author can pick whichever reads best.
    func testAbsenceFormsAgree() {
        let absent = [
            ElementCondition(label: "Spinner", exists: false),
            ElementCondition(label: "Spinner", count: 0),
            ElementCondition(label: "Spinner", maxCount: 0)
        ]
        for condition in absent {
            XCTAssertNil(condition.failureReason(in: screen), "\(condition.assertionDescription) should pass")
        }

        let present = [
            ElementCondition(label: "Sign In", exists: false),
            ElementCondition(label: "Sign In", count: 0),
            ElementCondition(label: "Sign In", maxCount: 0)
        ]
        for condition in present {
            XCTAssertNotNil(condition.failureReason(in: screen), "\(condition.assertionDescription) should fail")
        }
    }

    // MARK: - frame

    func testMinimumTouchTargetAssertion() {
        let roots = [node(label: "Tiny", width: 20, height: 20)]
        XCTAssertNil(ElementCondition(label: "Tiny", minWidth: 10, minHeight: 10).failureReason(in: roots))
        let reason = ElementCondition(label: "Tiny", minWidth: 44, minHeight: 44).failureReason(in: roots)
        XCTAssertEqual(reason, "expected width >= 44pt, found 20pt")
    }

    // MARK: - selector composition

    func testSelectorFieldsAreAnded() {
        XCTAssertNil(ElementCondition(label: "Row", elementType: "Cell", count: 3).failureReason(in: screen))
        XCTAssertNotNil(ElementCondition(label: "Row", elementType: "Button").failureReason(in: screen))
    }

    func testAssertsAbsenceDetection() {
        XCTAssertTrue(ElementCondition(label: "x", exists: false).assertsAbsence)
        XCTAssertTrue(ElementCondition(label: "x", count: 0).assertsAbsence)
        XCTAssertTrue(ElementCondition(label: "x", maxCount: 0).assertsAbsence)
        XCTAssertFalse(ElementCondition(label: "x", count: 1).assertsAbsence)
        XCTAssertFalse(ElementCondition(label: "x").assertsAbsence)
    }

    func testHasSelector() {
        XCTAssertTrue(ElementCondition(label: "x").hasSelector)
        XCTAssertTrue(ElementCondition(elementType: "Cell").hasSelector)
        XCTAssertFalse(ElementCondition(enabled: true).hasSelector)
    }
}
