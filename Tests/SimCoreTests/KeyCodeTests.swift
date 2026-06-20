// KeyCodeTests.swift
//
// Locks the ported AXe KeyCode table and the text -> HID event conversion.
// US-keyboard table; unsupported characters map to keyCode 0 / throw.

import XCTest
@testable import SimCore

final class KeyCodeTests: XCTestCase {

    func testLowercaseLetterNoShift() {
        let event = KeyEvent.keyCodeForString("a")
        XCTAssertEqual(event.keyCode, 4)
        XCTAssertFalse(event.shift)
    }

    func testUppercaseLetterRequiresShift() {
        let event = KeyEvent.keyCodeForString("A")
        XCTAssertEqual(event.keyCode, 4)
        XCTAssertTrue(event.shift)
    }

    func testShiftedSymbol() {
        let event = KeyEvent.keyCodeForString("!")
        XCTAssertEqual(event.keyCode, 30) // same usage as "1"
        XCTAssertTrue(event.shift)
    }

    func testUnsupportedCharacterMapsToZero() {
        let event = KeyEvent.keyCodeForString("é")
        XCTAssertEqual(event.keyCode, 0)
    }

    func testRoundTripStringForKeyCode() {
        let event = KeyEvent.keyCodeForString("Z")
        XCTAssertEqual(event.stringForKeyCode, "Z")
    }

    // MARK: - TextToHIDEvents

    func testSimpleCharacterIsDownThenUp() throws {
        let events = try TextToHIDEvents.convertTextToHIDEvents("a")
        XCTAssertEqual(events, [
            HIDKeyEvent(usage: 4, down: true),
            HIDKeyEvent(usage: 4, down: false)
        ])
    }

    func testShiftedCharacterWrapsInLeftShift() throws {
        let events = try TextToHIDEvents.convertTextToHIDEvents("A")
        XCTAssertEqual(events, [
            HIDKeyEvent(usage: TextToHIDEvents.leftShiftUsage, down: true),
            HIDKeyEvent(usage: 4, down: true),
            HIDKeyEvent(usage: 4, down: false),
            HIDKeyEvent(usage: TextToHIDEvents.leftShiftUsage, down: false)
        ])
    }

    func testMultiCharacterSequence() throws {
        let events = try TextToHIDEvents.convertTextToHIDEvents("ab")
        XCTAssertEqual(events, [
            HIDKeyEvent(usage: 4, down: true),
            HIDKeyEvent(usage: 4, down: false),
            HIDKeyEvent(usage: 5, down: true),
            HIDKeyEvent(usage: 5, down: false)
        ])
    }

    func testValidateTextRejectsNonUS() {
        XCTAssertTrue(TextToHIDEvents.validateText("Hello, World!"))
        XCTAssertFalse(TextToHIDEvents.validateText("café"))
    }

    func testUnsupportedCharacterThrows() {
        XCTAssertThrowsError(try TextToHIDEvents.convertTextToHIDEvents("é")) { error in
            guard case TextToHIDEvents.TextConversionError.unsupportedCharacter(let c) = error else {
                return XCTFail("expected unsupportedCharacter, got \(error)")
            }
            XCTAssertEqual(c, "é")
        }
    }
}
