// VerifySheetValidationTests.swift
//
// `verify-session sheet` sizes a bitmap from --rows and --height, so an
// unbounded value would overflow the layout arithmetic (a crash) or fail the
// allocation with an error that blames the captures. Parsing the real argument
// list pins that validate() stops both before anything is composed.

import XCTest
@testable import sipi

final class VerifySheetValidationTests: XCTestCase {
    func testOutOfRangeSizesAreRejectedAtParse() {
        for args in [["--height", "0"], ["--height", "9223372036854775807"], ["--height", "4001"],
                     ["--rows", "0"], ["--rows", "101"]] {
            XCTAssertThrowsError(try Sipi.VerifySession.Sheet.parse(["/tmp/verify"] + args), "\(args)")
        }
    }

    func testDefaultsParse() throws {
        let sheet = try Sipi.VerifySession.Sheet.parse(["/tmp/verify", "--device", "ipad"])
        XCTAssertEqual(sheet.rows, 3)
        XCTAssertEqual(sheet.height, 560)
        XCTAssertEqual(sheet.device, "ipad")
    }
}
