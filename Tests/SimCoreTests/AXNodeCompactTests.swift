// AXNodeCompactTests.swift
//
// Locks the compact describe-ui rendering: one element per line, indented by
// depth, with exactly the fields a driver acts on. The format is grep'd by
// agents, so the token shapes (`id="…"`, `frame=(x,y,w,h)`, `hit=(x,y)`,
// bare `disabled` / `offscreen`) are a contract.

import XCTest
@testable import SimCore

final class AXNodeCompactTests: XCTestCase {

    private func node(
        label: String? = nil, value: String? = nil, type: String? = nil, role: String? = nil,
        id: String? = nil, enabled: Bool? = nil, onscreen: Bool? = nil,
        frame: AXNode.Frame? = nil, hit: AXNode.Frame.Point? = nil, children: [AXNode]? = nil
    ) -> AXNode {
        AXNode(AXLabel: label, AXValue: value, role: role, type: type, AXUniqueId: id,
               enabled: enabled, frame: frame, hitPoint: hit, onscreen: onscreen, children: children)
    }

    func testRendersOneLinePerNodeIndentedByDepth() {
        let tree = [node(label: " ", role: "AXApplication", hit: .init(x: 201, y: 437), children: [
            node(label: "Sign In", type: "Button", id: "auth.sign-in",
                 frame: .init(x: 24.33, y: 88.0, width: 168.33, height: 44.0),
                 hit: .init(x: 108.49, y: 110.0)),
            node(type: "Group", children: [
                node(label: "Email", value: "", type: "TextField", id: "email",
                     frame: .init(x: 16, y: 200, width: 343, height: 44), hit: .init(x: 187.5, y: 222))
            ])
        ])]
        let expected = """
        Application " " hit=(201,437)
          Button "Sign In" id="auth.sign-in" frame=(24,88,168,44) hit=(108,110)
          Group
            TextField "Email" id="email" value="" frame=(16,200,343,44) hit=(188,222)

        """
        XCTAssertEqual(AXNodeCompact.string(for: tree), expected)
    }

    func testTypeFallsBackToRoleWithoutAXPrefixThenElement() {
        XCTAssertEqual(AXNodeCompact.line(for: node(role: "AXStaticText")), "StaticText")
        XCTAssertEqual(AXNodeCompact.line(for: node(type: "Cell", role: "AXCell")), "Cell")
        XCTAssertEqual(AXNodeCompact.line(for: node()), "Element")
    }

    func testDisabledAndOffscreenAreEmittedOnlyWhenFalse() {
        XCTAssertEqual(AXNodeCompact.line(for: node(type: "Button", enabled: true, onscreen: true)), "Button")
        XCTAssertEqual(AXNodeCompact.line(for: node(type: "Button", enabled: false)), "Button disabled")
        XCTAssertEqual(AXNodeCompact.line(for: node(type: "Cell", onscreen: false)), "Cell offscreen")
        XCTAssertEqual(
            AXNodeCompact.line(for: node(type: "Cell", enabled: false, onscreen: false)),
            "Cell disabled offscreen")
    }

    func testStringsAreQuotedAndEscaped() {
        let line = AXNodeCompact.line(for: node(label: "Say \"hi\"\nnow", value: "a\\b", type: "StaticText"))
        XCTAssertEqual(line, #"StaticText "Say \"hi\"\nnow" value="a\\b""#)
    }

    func testIdIsEmittedEvenWhenItEqualsTheLabel() {
        // A reader hunting for a selector must see that an id exists; folding it
        // into the label would hide the `--id` option.
        XCTAssertEqual(
            AXNodeCompact.line(for: node(label: "Maps", type: "Button", id: "Maps")),
            #"Button "Maps" id="Maps""#)
    }

    func testEmptyValueIsShownOnTextEntryOnly() {
        // An empty field is a fact worth a token; a container's empty value is
        // what the tree reports for "nothing" and would only add noise.
        XCTAssertEqual(AXNodeCompact.line(for: node(value: "", type: "TextField")), #"TextField value="""#)
        XCTAssertEqual(AXNodeCompact.line(for: node(value: "", type: "SecureTextField")), #"SecureTextField value="""#)
        XCTAssertEqual(AXNodeCompact.line(for: node(value: "", type: "Group")), "Group")
        XCTAssertEqual(AXNodeCompact.line(for: node(label: "Title", value: "", type: "StaticText")), #"StaticText "Title""#)
        XCTAssertEqual(AXNodeCompact.line(for: node(label: "Wi-Fi", value: "1", type: "Switch")), #"Switch "Wi-Fi" value="1""#)
    }

    func testEmptyTreeRendersEmptyString() {
        XCTAssertEqual(AXNodeCompact.string(for: []), "")
    }

    func testCoordinatesRoundToWholePointsAndNegativeZeroIsZero() {
        let line = AXNodeCompact.line(for: node(
            type: "Other", frame: .init(x: -0.2, y: 0.5, width: 10.49, height: 10.5)))
        XCTAssertEqual(line, "Other frame=(0,1,10,11)")
    }
}
