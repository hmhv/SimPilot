// DegenerateTreeTests.swift
//
// Locks `ChildTree.isDegenerate`, the classifier that separates "the app is not
// reachable yet" from "the selector is genuinely absent".
//
// Two callers depend on it, and both turn a wrong answer into a wrong result:
// `resolvingRoots` waits the tree out before resolving, and the `optional`
// pre-resolution refuses to call a target absent while the tree is degenerate.
// Without that second guard, a launch that has not settled turns an optional
// step into a passing skip for an element that was simply not up yet.

import XCTest
@testable import SimCore
@testable import sipi

final class DegenerateTreeTests: XCTestCase {

    private func node(
        label: String? = nil,
        children: [AXNode]? = nil,
        type: String = "Application"
    ) -> AXNode {
        AXNode(
            AXLabel: label,
            role: "AX\(type)",
            type: type,
            enabled: true,
            frame: AXNode.Frame(x: 0, y: 0, width: 0, height: 0),
            children: children
        )
    }

    // MARK: - Degenerate shapes

    func testEmptyTreeIsDegenerate() {
        XCTAssertTrue(ChildTree.isDegenerate([]))
    }

    func testSingleUnlabeledRootWithNoChildrenIsDegenerate() {
        XCTAssertTrue(ChildTree.isDegenerate([node()]))
    }

    func testSingleUnlabeledRootWithAnEmptyChildListIsDegenerate() {
        XCTAssertTrue(ChildTree.isDegenerate([node(children: [])]))
    }

    func testSingleRootWithAnEmptyLabelStringIsDegenerate() {
        XCTAssertTrue(ChildTree.isDegenerate([node(label: "")]))
    }

    // MARK: - Usable shapes

    func testSingleRootWithChildrenIsUsable() {
        XCTAssertFalse(ChildTree.isDegenerate([node(children: [node(label: "Continue", type: "Button")])]))
    }

    func testSingleLabeledRootIsUsable() {
        XCTAssertFalse(
            ChildTree.isDegenerate([node(label: "MyApp")]),
            "a labeled root is a real tree even with no children yet"
        )
    }

    func testMultipleRootsAreUsable() {
        XCTAssertFalse(
            ChildTree.isDegenerate([node(), node()]),
            "the degenerate shape is a SINGLE empty root; more than one root is a real answer"
        )
    }
}
