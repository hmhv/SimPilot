// BootedDeviceLineTests.swift
//
// `simctl list devices booted` is text, and the shape `<name> (<udid>) (Booted)`
// is only unambiguous read from the right — a device NAME can contain
// parentheses of its own.
//
// This is not hypothetical: simctl names the iPhone Duo "iPhone Duo (27.1)" when
// the plain name is taken on another runtime. Reading left to right took `27.1`
// as the UDID, so `isBooted` said false about a booted device and the harness
// then failed every run against it with "Unable to boot device in current state:
// Booted".

import Foundation
import XCTest
@testable import SimShell

final class BootedDeviceLineTests: XCTestCase {

    private func parse(_ line: String) -> SimShell.BootedDevice? {
        SimShell.parseBootedDeviceLine(line.trimmingCharacters(in: .whitespaces), runtime: "iOS 27.1").first
    }

    func testPlainDeviceLine() throws {
        let device = try XCTUnwrap(parse("    iPhone 17 (8ED16F54-995B-4243-AA71-C90C3593EE82) (Booted) "))
        XCTAssertEqual(device.name, "iPhone 17")
        XCTAssertEqual(device.udid, "8ED16F54-995B-4243-AA71-C90C3593EE82")
        XCTAssertEqual(device.runtime, "iOS 27.1")
    }

    /// Verbatim from `xcrun simctl list devices booted` on Xcode 27.1.
    func testNameContainingParenthesesKeepsTheRealUDID() throws {
        let device = try XCTUnwrap(
            parse("    iPhone Duo (27.1) (6B9E34DD-E57D-4A73-AFC7-44E067BDC2D5) (Booted) ")
        )
        XCTAssertEqual(device.udid, "6B9E34DD-E57D-4A73-AFC7-44E067BDC2D5")
        XCTAssertEqual(device.name, "iPhone Duo (27.1)", "the parenthesised part belongs to the name")
    }

    /// A user-renamed device can nest them.
    func testSeveralParenthesesInTheName() throws {
        let device = try XCTUnwrap(
            parse("    My (work) iPad (2) (11111111-2222-3333-4444-555555555555) (Booted)")
        )
        XCTAssertEqual(device.udid, "11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(device.name, "My (work) iPad (2)")
    }

    func testNameWithNoSpaceBeforeItsUDID() throws {
        let device = try XCTUnwrap(parse("Phone(11111111-2222-3333-4444-555555555555) (Booted)"))
        XCTAssertEqual(device.udid, "11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(device.name, "Phone")
    }

    func testLinesThatAreNotDevicesAreSkipped() {
        XCTAssertNil(parse(""))
        XCTAssertNil(parse("iPhone 17"))
        XCTAssertNil(parse("(Booted)"))
        XCTAssertNil(parse("== Devices =="))
    }
}
