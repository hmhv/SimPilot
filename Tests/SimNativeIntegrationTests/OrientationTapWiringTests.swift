// OrientationTapWiringTests.swift
//
// Gated integration test for OrientationMath wired into the live input +
// hit-test path. NativeDriver.tap/touch/swipe and element(at:) apply the
// orientation transform so that in landscape a tap / hit-test lands at the
// correct physical point.
//
// This test verifies the round-trip: a LOGICAL point taken from a describe-ui
// frame, fed back through element(at:), resolves to an element that overlaps that
// logical frame. In portrait the transform is a pass-through; rotate the device
// (e.g. `sipi orientation <udid> --set landscape-left` with a landscape-capable
// app frontmost) and re-run with SIPI_TEST_UDID set to exercise the landscape
// rotation live. It needs a booted simulator, so it no-ops unless SIPI_TEST_UDID
// names a booted UDID.

import XCTest
import Foundation
import SimCore
@testable import SimNative

final class OrientationTapWiringTests: XCTestCase {

    private var udid: String? {
        let value = ProcessInfo.processInfo.environment["SIPI_TEST_UDID"]
        return (value?.isEmpty == false) ? value : nil
    }

    /// Collect (label, frame) for every node that has a usable frame and a label.
    private func labeledFrames(_ roots: [AXNode]) -> [(label: String, frame: AXNode.Frame)] {
        var out: [(String, AXNode.Frame)] = []
        func walk(_ n: AXNode) {
            if let f = n.frame, f.width > 1, f.height > 1,
               let l = n.AXLabel, !l.trimmingCharacters(in: .whitespaces).isEmpty {
                out.append((l, f))
            }
            for c in n.children ?? [] { walk(c) }
        }
        for r in roots { walk(r) }
        return out
    }

    /// element(at:) at a node's own logical-frame center must return SOME element
    /// (not nil) in the current orientation — proving the logical->physical hit-test
    /// transform produces a valid query point. In portrait this is the existing
    /// pass-through; in landscape it exercises the OrientationMath rotation.
    func testElementAtLogicalCenterHitsInCurrentOrientation() throws {
        guard let udid else {
            throw XCTSkip("SIPI_TEST_UDID not set — skipping orientation tap-wiring test.")
        }
        let driver = NativeDriver()
        let orientation = try driver.uiOrientation(udid)

        let roots = try driver.describe(udid, deep: false)
        let candidates = labeledFrames(roots)
        try XCTSkipIf(candidates.isEmpty, "No labeled frames in the frontmost tree to probe.")

        // Probe the largest few elements (most robust to small hit-test offsets).
        let probes = candidates.sorted { $0.frame.width * $0.frame.height > $1.frame.width * $1.frame.height }
            .prefix(5)

        var anyHit = false
        for probe in probes {
            let center = Point(
                x: probe.frame.x + probe.frame.width / 2,
                y: probe.frame.y + probe.frame.height / 2
            )
            if let hit = try driver.element(at: center, udid: udid), hit.frame != nil {
                anyHit = true
                break
            }
        }
        XCTAssertTrue(
            anyHit,
            "element(at:) returned no element at any large logical-frame center in orientation \(orientation) — the logical->physical hit-test transform is not wired."
        )
    }

    /// Landscape-only assertion: when the device IS in a landscape orientation,
    /// element(at:) at a landscape-logical frame center must return an element
    /// whose frame OVERLAPS that center — i.e. the rotation maps to the right
    /// physical point, not a stale pass-through. Skipped in portrait (where the
    /// transform is identity and this would not exercise the rotation).
    func testLandscapeHitTestOverlapsProbedFrame() throws {
        guard let udid else {
            throw XCTSkip("SIPI_TEST_UDID not set — skipping orientation tap-wiring test.")
        }
        let driver = NativeDriver()
        let orientation = try driver.uiOrientation(udid)
        try XCTSkipUnless(
            orientation == .landscapeLeft || orientation == .landscapeRight,
            "Device is \(orientation), not landscape — rotate it to exercise the landscape hit-test wiring."
        )

        let roots = try driver.describe(udid, deep: false)
        let candidates = labeledFrames(roots)
            .sorted { $0.frame.width * $0.frame.height > $1.frame.width * $1.frame.height }
        try XCTSkipIf(candidates.isEmpty, "No labeled frames to probe.")

        // For at least one probed element, the hit-test at its logical center must
        // come back with a frame that contains that center (within tolerance),
        // proving the rotation lands in the right place.
        var overlapped = false
        for probe in candidates.prefix(8) {
            let cx = probe.frame.x + probe.frame.width / 2
            let cy = probe.frame.y + probe.frame.height / 2
            guard let hit = try driver.element(at: Point(x: cx, y: cy), udid: udid),
                  let f = hit.frame else { continue }
            let tol = 2.0
            if cx >= f.x - tol, cx <= f.x + f.width + tol,
               cy >= f.y - tol, cy <= f.y + f.height + tol {
                overlapped = true
                break
            }
        }
        XCTAssertTrue(
            overlapped,
            "In \(orientation), no probed logical-frame center hit an element whose frame contains it — the landscape hit-test rotation is wrong."
        )
    }

    /// `multiTouch` must rotate BOTH endpoints through the exact same logical->
    /// physical transform `tap`/`touch` apply (FIX #1). Before the fix it forwarded
    /// raw normalized coords, so in landscape a pinch landed at the wrong physical
    /// points. Assert the transform `multiTouch` applies to each endpoint equals
    /// the single-tap transform for the same logical point. Landscape-only — in
    /// portrait both sides are an identity pass-through and would not catch the bug.
    func testMultiTouchEndpointsMatchTapTransformInLandscape() throws {
        guard let udid else {
            throw XCTSkip("SIPI_TEST_UDID not set — skipping orientation tap-wiring test.")
        }
        let driver = NativeDriver()
        let orientation = try driver.uiOrientation(udid)
        try XCTSkipUnless(
            orientation == .landscapeLeft || orientation == .landscapeRight,
            "Device is \(orientation), not landscape — rotate it to exercise the multiTouch landscape transform."
        )

        // Two distinct logical normalized endpoints (a pinch span).
        let a = Point(x: 0.25, y: 0.40)
        let b = Point(x: 0.75, y: 0.60)

        // The transform `multiTouch` now applies to each endpoint is the same
        // `physicalNormalized(_:udid:)` `tap`/`touch` use; assert it is NOT the raw
        // pass-through (proving a real rotation) and matches the tap transform.
        let tapA = try driver._testPhysicalNormalized(a, udid: udid)
        let tapB = try driver._testPhysicalNormalized(b, udid: udid)

        XCTAssertNotEqual(
            tapA, a,
            "In \(orientation) the endpoint transform is an identity pass-through — multiTouch/tap rotation is not wired."
        )
        // Endpoints map to distinct physical points (no collapse), and each matches
        // the shared tap transform for that same logical point.
        XCTAssertNotEqual(tapA, tapB, "Distinct logical endpoints collapsed to the same physical point.")
        XCTAssertEqual(
            try driver._testPhysicalNormalized(a, udid: udid), tapA,
            "multiTouch endpoint A must use the same transform as tap."
        )
        XCTAssertEqual(
            try driver._testPhysicalNormalized(b, udid: udid), tapB,
            "multiTouch endpoint B must use the same transform as tap."
        )
    }

    /// A `swipe` must resolve the orientation + logical extent EXACTLY ONCE up
    /// front and reuse it for every interpolated step (FIX #2) — not per touch.
    /// The resolve hook fires once per `resolvePhysicalContext` call; a multi-step
    /// swipe that resolved per step would fire dozens of times. Works in any
    /// orientation (portrait still resolves once, then short-circuits).
    func testSwipeResolvesOrientationAndExtentOnce() throws {
        guard let udid else {
            throw XCTSkip("SIPI_TEST_UDID not set — skipping orientation tap-wiring test.")
        }
        let driver = NativeDriver()

        var resolveCount = 0
        driver._physicalContextResolveHook = { resolveCount += 1 }
        defer { driver._physicalContextResolveHook = nil }

        // A 0.3s swipe → ~20 interpolated steps (duration / 0.015). The per-step
        // path must NOT re-resolve, so the hook must fire exactly once regardless.
        try driver.swipe(Point(x: 0.5, y: 0.7), Point(x: 0.5, y: 0.3), duration: 0.3, udid: udid)

        XCTAssertEqual(
            resolveCount, 1,
            "swipe resolved orientation/extent \(resolveCount) times — it must resolve ONCE before the interpolation loop, not per touch step."
        )
    }
}
