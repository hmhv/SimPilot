// PathSafetyTests.swift
//
// Locks the single-path-component guard that keeps a JSON/CLI-authored id or
// check name from escaping the output directory via `../`.

import XCTest
@testable import SimCore

final class PathSafetyTests: XCTestCase {
    func testAcceptsPlainComponents() {
        XCTAssertTrue(PathSafety.isSafeComponent("login-flow"))
        XCTAssertTrue(PathSafety.isSafeComponent("test_01"))
        XCTAssertTrue(PathSafety.isSafeComponent("A.b"))
    }

    func testRejectsTraversalAndSeparators() {
        XCTAssertFalse(PathSafety.isSafeComponent(""))
        XCTAssertFalse(PathSafety.isSafeComponent("."))
        XCTAssertFalse(PathSafety.isSafeComponent(".."))
        XCTAssertFalse(PathSafety.isSafeComponent("../evil"))
        XCTAssertFalse(PathSafety.isSafeComponent("a/b"))
        XCTAssertFalse(PathSafety.isSafeComponent("/abs"))
        XCTAssertFalse(PathSafety.isSafeComponent("with\u{0}nul"))
    }
}
