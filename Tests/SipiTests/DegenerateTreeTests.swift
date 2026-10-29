// DegenerateTreeTests.swift
//
// Locks `ChildTree.isDegenerate`, the classifier that separates "the app is not
// reachable yet" from "the selector is genuinely absent".
//
// Its callers turn a wrong answer into a wrong result: `ChildTree.nodes`
// retries a degenerate in-process fetch in a child process, and `a11y-audit`,
// `wait-for` and `type` treat a degenerate tree as unreadable, which would
// otherwise read as "no defects", "gone", or "typed".

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
