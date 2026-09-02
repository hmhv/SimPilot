// LaunchctlListTests.swift
//
// Pure parse of `launchctl list` output from a simulator guest. The label
// grammar (`UIKitApplication:<bundle>[<hash>][rb-legacy]`) is what the
// memory-warning path relies on to turn a bundle id into a pid.

import XCTest
@testable import SimShell

final class LaunchctlListTests: XCTestCase {

    private let listing = """
    PID\tStatus\tLabel
    -\t0\tcom.apple.SafariBookmarksSyncAgent
    57819\t0\tUIKitApplication:com.simpilot.NetworkConditionFixture[b3ab][rb-legacy]
    -\t0\tUIKitApplication:com.simpilot.Stopped[9f00][rb-legacy]
    4242\t0\tUIKitApplication:com.simpilot.NetworkConditionFixture.ext[1111][rb-legacy]
    """

    func testFindsTheRunningJobForTheExactBundleID() {
        XCTAssertEqual(
            LaunchctlList.processIdentifier(in: listing, bundleID: "com.simpilot.NetworkConditionFixture"),
            57819)
    }

    func testDoesNotMatchAPrefixOfALongerBundleID() {
        XCTAssertEqual(
            LaunchctlList.processIdentifier(in: listing, bundleID: "com.simpilot.NetworkConditionFixture.ext"),
            4242)
        XCTAssertNil(LaunchctlList.processIdentifier(in: listing, bundleID: "com.simpilot"))
    }

    func testAJobWithoutALiveProcessIsNotRunning() {
        XCTAssertNil(LaunchctlList.processIdentifier(in: listing, bundleID: "com.simpilot.Stopped"))
    }

    func testMissingAppIsNil() {
        XCTAssertNil(LaunchctlList.processIdentifier(in: listing, bundleID: "com.example.absent"))
        XCTAssertNil(LaunchctlList.processIdentifier(in: "", bundleID: "com.example.absent"))
    }
}
