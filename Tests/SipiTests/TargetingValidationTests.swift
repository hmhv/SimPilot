// TargetingValidationTests.swift
//
// Locks the targeting contract for every command that accepts both coordinates
// and a selector: exactly one way to say where, and `--element-type` only
// alongside a selector.
//
// Driven through `ParsableCommand.parse`, not by calling `validateTargeting`
// directly. That is the point: the shared validator takes `elementType` as a
// defaulted parameter, so a command that forgets to pass it would still satisfy
// every direct-call test while silently accepting `-x -y --element-type` at the
// CLI. Parsing the real argument list is what pins the wiring.
//
// No simulator involved — validation runs before any command reaches a device.

import ArgumentParser
import XCTest
@testable import sipi

final class TargetingValidationTests: XCTestCase {
    private let udid = "00000000-0000-0000-0000-000000000000"

    /// Every command with the coordinates-or-selector contract, as the argument
    /// prefix its parser needs. `set-text` takes the text as a second positional.
    private lazy var commands: [(name: String, parse: ([String]) throws -> Void)] = [
        ("tap", { try Sipi.Tap.parse([self.udid] + $0) }),
        ("double-tap", { try Sipi.DoubleTap.parse([self.udid] + $0) }),
        ("set-text", { try Sipi.SetText.parse([self.udid, "hello"] + $0) })
    ]

    private func expectAccepted(_ args: [String], _ label: String) {
        for command in commands {
            XCTAssertNoThrow(try command.parse(args), "\(command.name) \(label)")
        }
    }

    private func expectRejected(_ args: [String], containing needle: String, _ label: String) {
        for command in commands {
            XCTAssertThrowsError(try command.parse(args), "\(command.name) \(label)") { error in
                let message = String(describing: error)
                XCTAssertTrue(
                    message.contains(needle),
                    "\(command.name) \(label): expected a message containing \"\(needle)\", got \(message)")
            }
        }
    }

    // MARK: - accepted

    func testCoordinatesAloneAreAccepted() {
        expectAccepted(["-x", "0.5", "-y", "0.5"], "coordinates alone")
    }

    func testSelectorAloneIsAccepted() {
        expectAccepted(["--label", "Sign In"], "label alone")
        expectAccepted(["--id", "auth.submit"], "id alone")
        expectAccepted(["--value", "42"], "value alone")
    }

    func testSelectorWithElementTypeIsAccepted() {
        expectAccepted(["--label", "Sign In", "--element-type", "Button"], "label + element-type")
        expectAccepted(["--id", "auth.submit", "--element-type", "Button"], "id + element-type")
    }

    // MARK: - rejected

    /// Accepting both and quietly preferring the coordinates makes a typo'd
    /// selector look like it resolved.
    func testCoordinatesWithSelectorAreRejected() {
        expectRejected(["-x", "0.5", "-y", "0.5", "--label", "Sign In"], containing: "not both",
                       "coordinates + label")
        expectRejected(["-x", "0.5", "-y", "0.5", "--id", "auth.submit"], containing: "not both",
                       "coordinates + id")
    }

    /// The regression this suite exists for. `--element-type` narrows a selector
    /// match; beside coordinates it constrains nothing, so a caller who passes it
    /// is expecting a type check that will never run.
    ///
    /// This also pins the WIRING: `validateTargeting` defaults `elementType` to
    /// nil, so a command that stops passing it fails here and nowhere else.
    func testCoordinatesWithElementTypeAreRejected() {
        expectRejected(["-x", "0.5", "-y", "0.5", "--element-type", "Button"],
                       containing: "--element-type only narrows",
                       "coordinates + element-type")
    }

    func testHalfACoordinateIsRejected() {
        expectRejected(["-x", "0.5"], containing: "must be provided together", "x alone")
        expectRejected(["-y", "0.5"], containing: "must be provided together", "y alone")
    }

    func testNoTargetIsRejected() {
        expectRejected([], containing: "Either provide both -x/-y", "no target")
    }

    func testMultipleSelectorsAreRejected() {
        expectRejected(["--label", "A", "--id", "B"], containing: "only one of", "label + id")
        expectRejected(["--label", "A", "--value", "C"], containing: "only one of", "label + value")
        expectRejected(["--id", "B", "--value", "C"], containing: "only one of", "id + value")
    }

    /// Each command names itself in the no-target message, so the guidance points
    /// at what the caller was actually running.
    func testRejectionNamesTheCommandsOwnVerb() {
        let verbs = ["tap": "to tap an element", "double-tap": "to double-tap an element",
                     "set-text": "to set text on an element"]
        for command in commands {
            XCTAssertThrowsError(try command.parse([])) { error in
                let message = String(describing: error)
                XCTAssertTrue(
                    message.contains(verbs[command.name] ?? "\u{0}"),
                    "\(command.name): expected its own verb in \(message)")
            }
        }
    }
}
