// HitPointTests.swift
//
// Locks the rules that keep a resolved touch on the screen.
//
// The bug these guard against was silent: an element scrolled out of view still
// resolved to the center of its frame, the injector accepted a coordinate the
// display does not have, the app never saw the touch, and the step reported
// success. So the invariants are (1) an off-screen element is reported as
// unreachable rather than given a point, (2) a partly visible element is touched
// inside its visible slice, and (3) a measured hit point from a hit-test
// overrides a frame that is not in screen space at all.
//
// Fixtures are hand-built — no simulator required.

import XCTest
import Foundation
@testable import SimCore

final class HitPointTests: XCTestCase {

    private let screen = AXNode.Frame(x: 0, y: 0, width: 400, height: 800)

    private func tree(_ children: [AXNode]) -> [AXNode] {
        [AXNode(
            AXLabel: "App", role: "AXApplication", type: "Application",
            frame: screen, children: children
        )]
    }

    private func node(
        id: String,
        type: String = "Button",
        frame: AXNode.Frame,
        hitPoint: AXNode.Frame.Point? = nil
    ) -> AXNode {
        AXNode(
            AXLabel: id, AXValue: "", role_description: "button",
            role: "AX" + type, type: type, AXUniqueId: id,
            enabled: true, frame: frame, hitPoint: hitPoint, children: []
        )
    }

    // MARK: - annotation

    func testFullyVisibleElementGetsItsCenter() throws {
        let roots = HitPoints.annotate(
            tree([node(id: "a", frame: .init(x: 100, y: 200, width: 80, height: 40))]),
            screen: screen
        )
        let a = try XCTUnwrap(roots[0].children?[0])
        XCTAssertEqual(a.onscreen, true)
        XCTAssertEqual(a.hitPoint, AXNode.Frame.Point(x: 140, y: 220))
    }

    func testElementTallerThanScreenIsTouchedInsideTheVisiblePart() throws {
        // 1400pt tall starting at y=220: the frame center is y=920, off screen.
        let roots = HitPoints.annotate(
            tree([node(id: "tall", frame: .init(x: 16, y: 220, width: 370, height: 1400))]),
            screen: screen
        )
        let tall = try XCTUnwrap(roots[0].children?[0])
        XCTAssertEqual(tall.onscreen, true)
        let point = try XCTUnwrap(tall.hitPoint)
        XCTAssertEqual(point.y, (220 + 800) / 2.0, accuracy: 0.001)
        XCTAssertLessThan(point.y, screen.height, "the touch must land on the display")
    }

    func testOffScreenElementGetsNoHitPoint() throws {
        let roots = HitPoints.annotate(
            tree([node(id: "below", frame: .init(x: 16, y: 1636, width: 370, height: 28))]),
            screen: screen
        )
        let below = try XCTUnwrap(roots[0].children?[0])
        XCTAssertEqual(below.onscreen, false)
        XCTAssertNil(below.hitPoint, "there is no honest point to offer for an unreachable element")
    }

    func testMeasuredHitPointSurvivesAnnotation() throws {
        // A remote view reports a frame local to itself; the probe point is the
        // only screen coordinate that reaches it.
        let measured = AXNode.Frame.Point(x: 64, y: 672)
        let roots = HitPoints.annotate(
            tree([node(id: "remote", frame: .init(x: 20, y: 108, width: 82, height: 120), hitPoint: measured)]),
            screen: screen
        )
        let remote = try XCTUnwrap(roots[0].children?[0])
        XCTAssertEqual(remote.hitPoint, measured)
        XCTAssertEqual(remote.onscreen, true)
    }

    // MARK: - resolution

    func testResolveTapReportsOffScreenElementAsUnreachable() throws {
        let roots = HitPoints.annotate(
            tree([node(id: "below", frame: .init(x: 16, y: 1636, width: 370, height: 28))]),
            screen: screen
        )
        let resolution = try AccessibilityTargetResolver.resolveTap(roots: roots, query: .id("below"))
        XCTAssertFalse(resolution.isOnScreen)
    }

    func testResolveTapUsesTheMeasuredPointWhenTheFrameIsNotScreenSpace() throws {
        let measured = AXNode.Frame.Point(x: 64, y: 672)
        let roots = HitPoints.annotate(
            tree([node(id: "remote", frame: .init(x: 20, y: 108, width: 82, height: 120), hitPoint: measured)]),
            screen: screen
        )
        let resolution = try AccessibilityTargetResolver.resolveTap(roots: roots, query: .id("remote"))
        XCTAssertEqual(resolution.point.x, 64, accuracy: 0.001)
        XCTAssertEqual(resolution.point.y, 672, accuracy: 0.001)
    }

    func testWideSwitchStillUsesItsTrailingEdge() throws {
        // A computed hit point (the clipped center) must not displace the
        // trailing-inset rule: the knob is at the trailing edge, not the middle.
        let toggle = AXNode(
            AXLabel: "Notifications", AXValue: "0", role_description: "switch",
            role: "AXSwitch", type: "Switch", AXUniqueId: "toggle",
            enabled: true, frame: .init(x: 16, y: 200, width: 370, height: 28), children: []
        )
        let roots = HitPoints.annotate(tree([toggle]), screen: screen)
        let resolution = try AccessibilityTargetResolver.resolveTap(roots: roots, query: .id("toggle"))
        XCTAssertEqual(resolution.point.x, 16 + 370 - 31, accuracy: 0.001)
        XCTAssertTrue(resolution.isSwitchLikeControl)
    }

    // MARK: - scroll direction

    func testScrollDirectionFollowsWhereTheElementIs() {
        let below = AXNode.Frame(x: 0, y: 1000, width: 100, height: 40)
        let above = AXNode.Frame(x: 0, y: -200, width: 100, height: 40)
        let right = AXNode.Frame(x: 900, y: 100, width: 100, height: 40)
        let visible = AXNode.Frame(x: 10, y: 10, width: 100, height: 40)
        XCTAssertEqual(ScrollIntoViewGeometry.direction(of: below, screen: screen), .contentBelow)
        XCTAssertEqual(ScrollIntoViewGeometry.direction(of: above, screen: screen), .contentAbove)
        XCTAssertEqual(ScrollIntoViewGeometry.direction(of: right, screen: screen), .contentRight)
        XCTAssertNil(ScrollIntoViewGeometry.direction(of: visible, screen: screen))
    }

    // MARK: - tap target check

    func testHitTestFindingNothingIsReportedRatherThanTapped() {
        let resolution = TapResolution(
            point: Point(x: 381, y: 503), isSwitchLikeControl: false,
            frame: .init(x: 360, y: 473, width: 160, height: 60),
            identifier: "chip-2", label: "CHIP-2"
        )
        XCTAssertEqual(TapTargetCheck.evaluate(target: resolution, hit: nil), .nothingThere)
    }

    func testAnyElementAtThePointCountsAsSomethingToTouch() {
        // The check answers "is there anything here", not "is this the right
        // control" — judging the latter from frames and identifiers rejected
        // real, working taps. See the note in TapTargetCheck.swift.
        let resolution = TapResolution(
            point: Point(x: 100, y: 100), isSwitchLikeControl: false,
            frame: .init(x: 80, y: 80, width: 100, height: 40),
            identifier: "row", label: "Row"
        )
        let inner = node(id: "row.title", type: "StaticText", frame: .init(x: 90, y: 90, width: 20, height: 10))
        XCTAssertTrue(TapTargetCheck.evaluate(target: resolution, hit: inner).isMatch)
    }

    func testScrollGestureFollowsTheTargetColumn() {
        // A vertical scroll must be dragged down the column the element is in,
        // not the middle of the screen, so it does not grab a neighbouring
        // scroller, a sheet, or a pager.
        let target = AXNode.Frame(x: 20, y: 1200, width: 80, height: 40)
        let points = ScrollIntoViewGeometry.swipePoints(
            for: .contentBelow, target: target, screen: screen
        )
        XCTAssertEqual(points.from.x, 60.0 / 400.0, accuracy: 0.001)
        XCTAssertEqual(points.from.x, points.to.x, accuracy: 0.001)
        XCTAssertGreaterThan(points.from.y, points.to.y, "content below means dragging upward")
    }

    func testScrollGestureIsRelativeToTheScreenOrigin() {
        let offsetScreen = AXNode.Frame(x: 100, y: 50, width: 400, height: 800)
        let target = AXNode.Frame(x: 120, y: 1200, width: 80, height: 40)
        let points = ScrollIntoViewGeometry.swipePoints(
            for: .contentBelow, target: target, screen: offsetScreen
        )
        XCTAssertEqual(points.from.x, 60.0 / 400.0, accuracy: 0.001)
    }

    func testScrollGestureStaysOffTheScreenEdges() {
        // An element hard against the edge must not produce an edge swipe, which
        // the system would read as back-navigation or Control Centre.
        let target = AXNode.Frame(x: 0, y: 1200, width: 4, height: 40)
        let points = ScrollIntoViewGeometry.swipePoints(
            for: .contentBelow, target: target, screen: screen
        )
        XCTAssertGreaterThanOrEqual(points.from.x, 0.1)
    }

    func testAnExplicitlyOffScreenFlagWinsOverAMeasuredPoint() throws {
        // A probe on the exclusive edge of the grid is not a touchable point.
        var edge = node(id: "edge", frame: .init(x: 380, y: 100, width: 20, height: 20))
        edge.hitPoint = AXNode.Frame.Point(x: 400, y: 110)
        edge.onscreen = false
        let roots = tree([edge])
        let resolution = try AccessibilityTargetResolver.resolveTap(roots: roots, query: .id("edge"))
        XCTAssertFalse(resolution.isOnScreen)
    }
}
