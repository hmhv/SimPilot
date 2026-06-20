// AXNodeJSONContractTests.swift
//
// Locks the describe-ui JSON contract. Rather than a brittle byte-for-byte
// golden file, it asserts TWO things, because JSONSerialization does not
// guarantee key order:
//
//   1. VERIFY-FORM    — the pretty-print output contains spaced-colon
//                       `"AXLabel" : "value"` lines that skills grep as raw text
//                       (protects run.md:60-61).
//   2. STRUCTURAL-SHAPE — decoding the output yields a top-level array whose
//                       root[0] carries frame{x,y,width,height}, and nodes carry
//                       the documented field names and nesting that `sipi`
//                       consumes (protects ui_tap_id / ui_tap_label and the
//                       System-UI node-count fallback).
//
// Fixtures are hand-built — no simulator required.

import XCTest
import Foundation
@testable import SimCore

final class AXNodeJSONContractTests: XCTestCase {

    /// A small but representative describe-ui tree: a root container with a
    /// frame and two children (a button and a switch), exercising every
    /// documented field including the optional raw `role` and `subrole`.
    private func fixtureTree() -> [AXNode] {
        let button = AXNode(
            AXLabel: "Continue",
            AXValue: "",
            role_description: "button",
            role: "AXButton",
            type: "Button",
            AXUniqueId: "continue-button",
            enabled: true,
            frame: AXNode.Frame(x: 20, y: 400, width: 280, height: 44)
        )
        let toggle = AXNode(
            AXLabel: "Wi-Fi",
            AXValue: "1",
            role_description: "switch",
            role: "AXSwitch",
            type: "Switch",
            subrole: "AXToggle",
            AXUniqueId: "wifi-toggle",
            enabled: true,
            frame: AXNode.Frame(x: 20, y: 460, width: 280, height: 31)
        )
        let root = AXNode(
            AXLabel: "Settings",
            AXValue: "",
            role_description: "window",
            role: "AXWindow",
            type: "Window",
            AXUniqueId: "",
            enabled: true,
            frame: AXNode.Frame(x: 0, y: 0, width: 390, height: 844),
            children: [button, toggle]
        )
        return [root]
    }

    // MARK: - Assertion 1: verify-form (spaced colon)

    func testVerifyFormSpacedColon() throws {
        let json = try AXNode.encodeTreeJSON(fixtureTree())

        // Every emitted string field must appear as `"key" : "value"` with the
        // single space on each side of the colon that JSONSerialization
        // .prettyPrinted produces. Skills grep these lines verbatim.
        let labelRegex = try NSRegularExpression(
            pattern: #""AXLabel" : "[^"]*""#
        )
        let labelMatches = labelRegex.numberOfMatches(
            in: json,
            range: NSRange(json.startIndex..., in: json)
        )
        XCTAssertGreaterThanOrEqual(
            labelMatches, 1,
            "expected at least one spaced-colon \"AXLabel\" : \"...\" line; got:\n\(json)"
        )

        // The exact button label line must be present verbatim.
        XCTAssertTrue(
            json.contains(#""AXLabel" : "Continue""#),
            "expected verbatim spaced-colon AXLabel line; got:\n\(json)"
        )

        // The spaced-colon style is global, not just for AXLabel.
        XCTAssertTrue(
            json.contains(#""AXUniqueId" : "continue-button""#),
            "expected spaced-colon AXUniqueId line; got:\n\(json)"
        )
        XCTAssertFalse(
            json.contains(#""AXLabel":"#),
            "found compact (unspaced) colon — breaks the verify-form contract:\n\(json)"
        )
    }

    // MARK: - Assertion 2: structural shape

    func testStructuralShapeTopLevelArrayAndFields() throws {
        let json = try AXNode.encodeTreeJSON(fixtureTree())
        let data = Data(json.utf8)

        let decoded = try JSONSerialization.jsonObject(with: data)

        // Top-level array.
        guard let array = decoded as? [Any] else {
            return XCTFail("describe-ui output must decode to a top-level array; got \(type(of: decoded))")
        }
        XCTAssertEqual(array.count, 1, "fixture has a single root")

        // root[0] is an object carrying the documented fields.
        guard let root = array.first as? [String: Any] else {
            return XCTFail("root[0] must be a JSON object")
        }

        // root[0] carries frame{x,y,width,height}.
        guard let frame = root["frame"] as? [String: Any] else {
            return XCTFail("root[0] must carry a frame object")
        }
        for key in ["x", "y", "width", "height"] {
            XCTAssertNotNil(frame[key], "frame must carry \(key)")
            XCTAssertTrue(frame[key] is NSNumber, "frame.\(key) must be numeric")
        }
        XCTAssertEqual(frame["width"] as? Double, 390)
        XCTAssertEqual(frame["height"] as? Double, 844)

        // root[0] carries the documented node field names.
        XCTAssertNotNil(root["AXLabel"])
        XCTAssertNotNil(root["AXValue"])
        XCTAssertNotNil(root["AXUniqueId"])
        XCTAssertNotNil(root["type"])
        XCTAssertNotNil(root["role_description"])
        XCTAssertNotNil(root["enabled"])
        XCTAssertTrue(root["enabled"] is NSNumber, "enabled must be a bool/number")

        // Nesting: children is an array of objects with the same shape.
        guard let children = root["children"] as? [Any] else {
            return XCTFail("root[0] must carry a children array")
        }
        XCTAssertEqual(children.count, 2, "fixture root has two children")
        guard let firstChild = children.first as? [String: Any] else {
            return XCTFail("children[0] must be a JSON object")
        }
        XCTAssertEqual(firstChild["AXLabel"] as? String, "Continue")
        XCTAssertEqual(firstChild["AXUniqueId"] as? String, "continue-button")
        XCTAssertNotNil(firstChild["frame"] as? [String: Any], "child must carry a frame")

        // Gate 2 fidelity: raw `role` and optional `subrole` survive the round-trip.
        XCTAssertEqual(firstChild["role"] as? String, "AXButton")
        guard let secondChild = children[1] as? [String: Any] else {
            return XCTFail("children[1] must be a JSON object")
        }
        XCTAssertEqual(secondChild["subrole"] as? String, "AXToggle")
    }

    /// The Codable model itself round-trips through the encoder shape (decoding
    /// the encoded output back into [AXNode] preserves the tree).
    func testCodableRoundTrip() throws {
        let tree = fixtureTree()
        let json = try AXNode.encodeTreeJSON(tree)
        let decoded = try JSONDecoder().decode([AXNode].self, from: Data(json.utf8))
        XCTAssertEqual(decoded, tree)
    }
}
