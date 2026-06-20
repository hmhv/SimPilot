// InProcessAXFetchTests.swift
//
// Gated integration test for the AccessibilityPlatformTranslation in-process
// token lifecycle.
//
// Background: AXPTranslator caches the AXPMacPlatformElement it builds for the
// frontmost application and pins it to the bridge-delegate token of the FIRST
// fetch. The earlier code minted a fresh token per fetch and evicted it after
// the call, so a SECOND in-process fetch handed back the cached element whose
// backing AX requests dispatched through the now-evicted token — the callback
// could no longer resolve a device and returned an empty response, degenerating
// the tree to an empty-label root with no children. The fix uses one stable
// token per device that is never evicted (SimBridge -stableTokenForDevice:udid:).
//
// This test exercises that fix end-to-end through SimNative. It needs a booted
// simulator, so it no-ops unless SIPI_TEST_UDID names a booted UDID — that keeps
// `swift test` green on a simulator-free CI box while still proving the fix on a
// machine that exports the UDID.

import XCTest
import Foundation
import SimCore
import SimNative

final class InProcessAXFetchTests: XCTestCase {

    /// The booted UDID to test against, or nil to skip (no simulator available).
    private var udid: String? {
        let value = ProcessInfo.processInfo.environment["SIPI_TEST_UDID"]
        return (value?.isEmpty == false) ? value : nil
    }

    /// Count every node in a tree (root + all descendants).
    private func nodeCount(_ roots: [AXNode]) -> Int {
        roots.reduce(0) { $0 + 1 + nodeCount($1.children ?? []) }
    }

    /// Two sequential in-process fast fetches in the SAME process must BOTH
    /// return a populated tree (> 1 node). Before the stable-token fix the second
    /// fetch returned a degenerate single-node root.
    func testRepeatedInProcessFastFetchesBothFull() throws {
        guard let udid else {
            throw XCTSkip("SIPI_TEST_UDID not set — skipping in-process AX integration test.")
        }
        let driver = NativeDriver()

        let first = try driver.describe(udid, deep: false)
        let firstCount = nodeCount(first)
        XCTAssertGreaterThan(firstCount, 1, "First in-process fetch should return a populated tree.")

        let second = try driver.describe(udid, deep: false)
        let secondCount = nodeCount(second)
        XCTAssertGreaterThan(
            secondCount, 1,
            "Second in-process fetch returned a degenerate root (\(secondCount) node) — the APT token-lifecycle regression is back."
        )

        // A third fetch must also stay full, proving the token stays resolvable
        // for the bridge's lifetime rather than only surviving one extra call.
        let third = try driver.describe(udid, deep: false)
        XCTAssertGreaterThan(nodeCount(third), 1, "Third in-process fetch should still return a populated tree.")
    }

    /// A deep fetch (grid pass) after a fast fetch — both in-process — must each
    /// stay populated, and the deep pass must surface at least as many nodes as
    /// the fast one (it augments, never shrinks).
    func testFastThenDeepInProcessBothFull() throws {
        guard let udid else {
            throw XCTSkip("SIPI_TEST_UDID not set — skipping in-process AX integration test.")
        }
        let driver = NativeDriver()

        let fast = try driver.describe(udid, deep: false)
        XCTAssertGreaterThan(nodeCount(fast), 1, "Fast in-process fetch should return a populated tree.")

        let deep = try driver.describe(udid, deep: true)
        XCTAssertGreaterThan(
            nodeCount(deep), 1,
            "Deep in-process fetch after a fast one returned a degenerate root — token-lifecycle regression."
        )
        XCTAssertGreaterThanOrEqual(
            nodeCount(deep), nodeCount(fast),
            "Deep pass should augment the fast tree, not shrink it."
        )
    }
}
