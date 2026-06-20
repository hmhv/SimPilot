// AccessibilityResolverTests.swift
//
// Locks the ported AXe resolution logic. Resolving a known label / id / value
// against a hand-built AXNode fixture tree
// must return the right node and a sane activation point, and a wide switch's
// activation point must reflect the trailing inset (31pt at width > 100pt).
//
// Fixtures are hand-built — no simulator required.

import XCTest
import Foundation
@testable import SimCore

final class AccessibilityResolverTests: XCTestCase {

    /// A representative tree: an Application root containing a labeled button,
    /// a Wi-Fi row (a static label sitting beside a wide switch under a shared
    /// container), and a narrow standalone toggle.
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

        // A Wi-Fi row: a non-actionable label next to a wide switch, both under
        // a shared container. Exercises the actionable-ancestor sibling redirect
        // for --label and the wide-switch trailing inset.
        let wifiLabel = AXNode(
            AXLabel: "Wi-Fi",
            role_description: "text",
            role: "AXStaticText",
            type: "StaticText",
            AXUniqueId: "wifi-label",
            enabled: true,
            frame: AXNode.Frame(x: 20, y: 460, width: 80, height: 31)
        )
        let wideSwitch = AXNode(
            AXValue: "1",
            role_description: "switch",
            role: "AXSwitch",
            type: "Switch",
            subrole: "AXToggle",
            AXUniqueId: "wifi-switch",
            enabled: true,
            frame: AXNode.Frame(x: 20, y: 460, width: 280, height: 31)
        )
        let wifiRow = AXNode(
            role_description: "group",
            role: "AXGroup",
            type: "Other",
            AXUniqueId: "wifi-row",
            enabled: true,
            frame: AXNode.Frame(x: 20, y: 460, width: 280, height: 31),
            children: [wifiLabel, wideSwitch]
        )

        // A narrow standalone toggle (width <= 100pt) — center activation.
        let narrowToggle = AXNode(
            AXLabel: "Bluetooth",
            AXValue: "0",
            role_description: "switch",
            role: "AXSwitch",
            type: "Switch",
            AXUniqueId: "bluetooth-switch",
            enabled: true,
            frame: AXNode.Frame(x: 250, y: 520, width: 51, height: 31)
        )

        let root = AXNode(
            AXLabel: "Settings",
            role_description: "application",
            role: "AXApplication",
            type: "Application",
            AXUniqueId: "settings-app",
            enabled: true,
            frame: AXNode.Frame(x: 0, y: 0, width: 390, height: 844),
            children: [button, wifiRow, narrowToggle]
        )
        return [root]
    }

    // MARK: - Resolve by id / label / value

    func testResolveByIdReturnsRightNode() throws {
        let match = try AccessibilityTargetResolver.resolveElement(
            roots: fixtureTree(),
            query: .id("continue-button")
        )
        XCTAssertEqual(match.element.AXUniqueId, "continue-button")
        XCTAssertEqual(match.element.AXLabel, "Continue")
        XCTAssertEqual(match.selectorDescription, "--id 'continue-button'")
        // Application frame is reported for coordinate context.
        XCTAssertEqual(match.applicationFrame?.width, 390)
    }

    func testResolveByLabelReturnsActionableNode() throws {
        let match = try AccessibilityTargetResolver.resolveElement(
            roots: fixtureTree(),
            query: .label("Continue")
        )
        XCTAssertEqual(match.element.AXUniqueId, "continue-button")
        XCTAssertTrue(match.element.isActionable)
    }

    func testResolveByValueReturnsRightNode() throws {
        let match = try AccessibilityTargetResolver.resolveElement(
            roots: fixtureTree(),
            query: .value("0")
        )
        // Only the narrow toggle carries value "0".
        XCTAssertEqual(match.element.AXUniqueId, "bluetooth-switch")
    }

    // MARK: - Activation points

    func testTapPointForButtonIsCenter() throws {
        let resolution = try AccessibilityTargetResolver.resolveTap(
            roots: fixtureTree(),
            query: .id("continue-button")
        )
        // Center of frame (20, 400, 280, 44).
        XCTAssertEqual(resolution.point.x, 20 + 280 / 2.0, accuracy: 0.0001)
        XCTAssertEqual(resolution.point.y, 400 + 44 / 2.0, accuracy: 0.0001)
        XCTAssertFalse(resolution.isSwitchLikeControl)
    }

    /// Gate 3: a wide switch (width > 100pt) is tapped at the trailing inset
    /// (frame.x + frame.width - 31), not the center.
    func testWideSwitchActivationPointReflectsTrailingInset() throws {
        let resolution = try AccessibilityTargetResolver.resolveTap(
            roots: fixtureTree(),
            query: .id("wifi-switch")
        )
        // Frame (20, 460, 280, 31): trailing inset point is x = 20 + 280 - 31.
        XCTAssertEqual(resolution.point.x, 20 + 280 - 31, accuracy: 0.0001)
        XCTAssertEqual(resolution.point.y, 460 + 31 / 2.0, accuracy: 0.0001)
        XCTAssertTrue(resolution.isSwitchLikeControl)
        // The trailing-inset point must NOT be the geometric center.
        XCTAssertNotEqual(resolution.point.x, 20 + 280 / 2.0, accuracy: 0.0001)
    }

    /// A narrow switch (width <= 100pt) keeps the geometric-center activation.
    func testNarrowSwitchActivationPointIsCenter() throws {
        let resolution = try AccessibilityTargetResolver.resolveTap(
            roots: fixtureTree(),
            query: .id("bluetooth-switch")
        )
        // Frame (250, 520, 51, 31): center, because 51 <= 100pt threshold.
        XCTAssertEqual(resolution.point.x, 250 + 51 / 2.0, accuracy: 0.0001)
        XCTAssertEqual(resolution.point.y, 520 + 31 / 2.0, accuracy: 0.0001)
        XCTAssertTrue(resolution.isSwitchLikeControl)
    }

    /// Gate 3: a --label match on a non-actionable static text redirects to the
    /// single sibling switch under the shared ancestor, and tapping it lands at
    /// the wide-switch trailing inset.
    func testLabelSiblingRedirectToSwitch() throws {
        let resolution = try AccessibilityTargetResolver.resolveTap(
            roots: fixtureTree(),
            query: .label("Wi-Fi")
        )
        XCTAssertTrue(resolution.isSwitchLikeControl)
        XCTAssertEqual(resolution.point.x, 20 + 280 - 31, accuracy: 0.0001)
        XCTAssertEqual(resolution.point.y, 460 + 31 / 2.0, accuracy: 0.0001)
    }

    // MARK: - Errors

    func testNotFoundThrows() {
        XCTAssertThrowsError(
            try AccessibilityTargetResolver.resolveElement(
                roots: fixtureTree(),
                query: .id("does-not-exist")
            )
        ) { error in
            guard let error = error as? ElementResolutionError else {
                return XCTFail("expected ElementResolutionError, got \(error)")
            }
            XCTAssertTrue(error.isNotFound)
        }
    }

    // MARK: - Poller

    func testPollerResolvesOnFirstFetch() async throws {
        let tree = fixtureTree()
        let resolution = try await AccessibilityPoller.resolveTapWithPolling(
            query: .id("continue-button"),
            waitTimeout: 0,
            pollInterval: 0.01,
            rootsFetcher: { tree }
        )
        XCTAssertFalse(resolution.isSwitchLikeControl)
        XCTAssertEqual(resolution.point.x, 20 + 280 / 2.0, accuracy: 0.0001)
    }

    func testPollerRetriesUntilElementAppears() async throws {
        let tree = fixtureTree()
        let attempts = AttemptCounter()
        let resolution = try await AccessibilityPoller.resolveTapWithPolling(
            query: .id("continue-button"),
            waitTimeout: 1.0,
            pollInterval: 0.02,
            rootsFetcher: {
                // Empty on the first attempt, then the populated tree.
                attempts.value < 1 ? { attempts.value += 1; return [] }() : tree
            }
        )
        XCTAssertEqual(resolution.point.y, 400 + 44 / 2.0, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(attempts.value, 1)
    }

    /// A trivial mutable counter for the polling test (the fetcher closure is
    /// non-escaping and runs serially, so no synchronization is required).
    private final class AttemptCounter {
        var value = 0
    }
}
