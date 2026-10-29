// ElementConditionTests.swift
//
// Locks element existence and absence, and how the selector fields combine.

import XCTest
@testable import SimCore

final class ElementConditionTests: XCTestCase {

    private func node(
        label: String? = nil,
        id: String? = nil,
        value: String? = nil,
        type: String = "Button"
    ) -> AXNode {
        AXNode(
            AXLabel: label,
            AXValue: value,
            role: "AX" + type,
            type: type,
            AXUniqueId: id,
            enabled: true,
            frame: AXNode.Frame(x: 0, y: 0, width: 100, height: 44)
        )
    }

    private lazy var screen: [AXNode] = [
        AXNode(type: "Window", children: [
            node(label: "Sign In", id: "auth.submit"),
            node(label: "Email", id: "auth.email", value: "user@example.com", type: "TextField"),
            node(label: "Row", id: "row.1", type: "Cell"),
            node(label: "Row", id: "row.2", type: "Cell")
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

    // MARK: - value as a selector

    func testValueSelectsAnElement() {
        XCTAssertNil(ElementCondition(value: "user@example.com").failureReason(in: screen))
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

    // MARK: - selector composition

    func testSelectorFieldsAreAnded() {
        XCTAssertNil(ElementCondition(label: "Row", elementType: "Cell").failureReason(in: screen))
        XCTAssertNotNil(ElementCondition(label: "Row", elementType: "Button").failureReason(in: screen))
    }
}
