// BootedDeviceLineTests.swift
//
// `simctl list devices booted` is text, and the shape `<name> (<udid>) (Booted)`
// is only unambiguous read from the right — a device NAME can contain
// parentheses of its own.
//
// This is not hypothetical: simctl names a device after its runtime — "iPhone Duo
// (27.2)" — when the plain name is taken on another runtime. Reading left to right took `27.2`
// as the UDID, so `isBooted` said false about a booted device and a caller
// then failed every run against it with "Unable to boot device in current state:
// Booted".

import Foundation
import XCTest
@testable import SimShell

final class BootedDeviceLineTests: XCTestCase {

    private func parse(_ line: String) -> SimShell.BootedDevice? {
        SimShell.parseBootedDeviceLine(line.trimmingCharacters(in: .whitespaces), runtime: "iOS 27.2").first
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
