// OrientationMathTests.swift
//
// Locks the ported AXe logical<->physical coordinate translation used by taps in
// landscape. Pure Foundation: no simulator, no SimBridge. Geometry is checked
// against a known portrait extent so a regression
// in the rotation math (which would land taps in the wrong place when rotated)
// fails here.

import XCTest
@testable import SimCore

final class OrientationMathTests: XCTestCase {

    // A representative device: 390 x 844 logical points in portrait.
    private let w = 390.0
    private let h = 844.0

    private func assertClose(
        _ point: Point,
        _ expectedX: Double,
        _ expectedY: Double,
        accuracy: Double = 1e-9,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(point.x, expectedX, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(point.y, expectedY, accuracy: accuracy, file: file, line: line)
    }

    func testPortraitIsIdentity() {
        let p = OrientationMath.translateToPhysical(
            x: 100, y: 200, orientation: .portrait,
            portraitWidth: w, portraitHeight: h
        )
        assertClose(p, 100, 200)
    }

    func testPortraitUpsideDownIs180() {
        let p = OrientationMath.translateToPhysical(
            x: 100, y: 200, orientation: .portraitUpsideDown,
            portraitWidth: w, portraitHeight: h
        )
        assertClose(p, w - 100, h - 200)
    }

    func testLandscapeLeftRotation() {
        // Logical (x, y) -> physical (y, portraitHeight - x).
        let p = OrientationMath.translateToPhysical(
            x: 100, y: 200, orientation: .landscapeLeft,
            portraitWidth: w, portraitHeight: h
        )
        assertClose(p, 200, h - 100)
    }

    func testLandscapeRightRotation() {
        // Logical (x, y) -> physical (portraitWidth - y, x).
        let p = OrientationMath.translateToPhysical(
            x: 100, y: 200, orientation: .landscapeRight,
            portraitWidth: w, portraitHeight: h
        )
        assertClose(p, w - 200, 100)
    }

    func testLandscapeOriginMapsToCorner() {
        // The logical origin in landscape-left maps to the bottom-left physical
        // corner (0, portraitHeight); landscape-right maps to the top-right.
        let left = OrientationMath.translateToPhysical(
            x: 0, y: 0, orientation: .landscapeLeft,
            portraitWidth: w, portraitHeight: h
        )
        assertClose(left, 0, h)

        let right = OrientationMath.translateToPhysical(
            x: 0, y: 0, orientation: .landscapeRight,
            portraitWidth: w, portraitHeight: h
        )
        assertClose(right, w, 0)
    }

    func testLetterboxParametersCenterUniformly() {
        // A 800x600 logical rect inside a 1000x1000 physical rect: scale to fit
        // the wider axis (1000/800 vs 1000/600 -> min = 1.25) and center.
        let params = OrientationMath.letterboxParameters(
            logicalWidth: 800, logicalHeight: 600,
            physicalWidth: 1000, physicalHeight: 1000
        )
        XCTAssertEqual(params.scale, 1000.0 / 800.0, accuracy: 1e-9)
        XCTAssertEqual(params.offsetX, 0, accuracy: 1e-9)
        XCTAssertEqual(params.offsetY, (1000 - 600 * (1000.0 / 800.0)) / 2, accuracy: 1e-9)
    }

    func testLetterboxParametersGuardZeroExtent() {
        // No usable logical extent -> identity (unit scale, zero offsets) instead
        // of dividing by zero.
        let params = OrientationMath.letterboxParameters(
            logicalWidth: 0, logicalHeight: 600,
            physicalWidth: 1000, physicalHeight: 1000
        )
        XCTAssertEqual(params.scale, 1)
        XCTAssertEqual(params.offsetX, 0)
        XCTAssertEqual(params.offsetY, 0)
    }

    func testLetterboxToPhysicalAppliesScaleAndOffset() {
        let p = OrientationMath.letterboxToPhysical(
            x: 100, y: 50, scale: 2, offsetX: 10, offsetY: 20
        )
        assertClose(p, 10 + 100 * 2, 20 + 50 * 2)
    }

    // MARK: - physicalExtent

    func testPhysicalExtentPortraitPassesThrough() {
        let e = OrientationMath.physicalExtent(
            logicalWidth: w, logicalHeight: h, orientation: .portrait
        )
        XCTAssertEqual(e.width, w, accuracy: 1e-9)
        XCTAssertEqual(e.height, h, accuracy: 1e-9)
    }

    func testPhysicalExtentUpsideDownPassesThrough() {
        let e = OrientationMath.physicalExtent(
            logicalWidth: w, logicalHeight: h, orientation: .portraitUpsideDown
        )
        XCTAssertEqual(e.width, w, accuracy: 1e-9)
        XCTAssertEqual(e.height, h, accuracy: 1e-9)
    }

    func testPhysicalExtentLandscapeSwapsAxes() {
        // describe-ui reports a landscape tree as (h x w); the physical framebuffer
        // stays portrait (w x h).
        for orientation in [UIOrientation.landscapeLeft, .landscapeRight] {
            let e = OrientationMath.physicalExtent(
                logicalWidth: h, logicalHeight: w, orientation: orientation
            )
            XCTAssertEqual(e.width, w, accuracy: 1e-9)
            XCTAssertEqual(e.height, h, accuracy: 1e-9)
        }
    }

    // MARK: - normalizedToPhysical (the live tap/hit-test wiring)

    func testNormalizedToPhysicalPortraitIsIdentity() {
        let p = OrientationMath.normalizedToPhysical(
            normalizedX: 0.3, normalizedY: 0.7, orientation: .portrait,
            logicalWidth: w, logicalHeight: h
        )
        assertClose(p, 0.3, 0.7)
    }

    func testNormalizedToPhysicalLandscapeLeftAddressBarMapsToExpectedPoint() {
        // Live-derived case (iPhone 16, iOS 26.4, Safari, landscape-left): the
        // address bar at landscape-logical center (426, 32) of an 852x393 tree maps
        // to physical-normalized (~0.0814, 0.5). A tap there activates it.
        let logicalW = 852.0, logicalH = 393.0       // landscape tree extent
        let nx = 426.0 / logicalW                     // 0.5
        let ny = 32.0 / logicalH                      // ~0.0814
        let p = OrientationMath.normalizedToPhysical(
            normalizedX: nx, normalizedY: ny, orientation: .landscapeLeft,
            logicalWidth: logicalW, logicalHeight: logicalH
        )
        // Physical extent is 393x852; expected physical point (32, 426).
        assertClose(p, 32.0 / 393.0, 426.0 / 852.0, accuracy: 1e-6)
    }

    func testNormalizedToPhysicalLandscapeLeftCornerMapping() {
        // Landscape-logical origin (top-left of the rotated UI) maps to the
        // bottom-left physical corner: translateToPhysical landscapeLeft maps
        // (0,0) -> (0, physicalHeight), i.e. physical-norm (0, 1).
        let logicalW = 852.0, logicalH = 393.0
        let p = OrientationMath.normalizedToPhysical(
            normalizedX: 0, normalizedY: 0, orientation: .landscapeLeft,
            logicalWidth: logicalW, logicalHeight: logicalH
        )
        assertClose(p, 0, 1, accuracy: 1e-9)
    }

    func testNormalizedToPhysicalLandscapeRightCornerMapping() {
        // Landscape-right mirrors left: logical origin -> top-right physical corner
        // (physicalWidth, 0), i.e. physical-norm (1, 0).
        let logicalW = 852.0, logicalH = 393.0
        let p = OrientationMath.normalizedToPhysical(
            normalizedX: 0, normalizedY: 0, orientation: .landscapeRight,
            logicalWidth: logicalW, logicalHeight: logicalH
        )
        assertClose(p, 1, 0, accuracy: 1e-9)
    }

    func testNormalizedToPhysicalUpsideDownIs180() {
        // Upside-down: physical extent equals logical extent (axes line up), and a
        // normalized point maps to its 180° opposite (1-nx, 1-ny).
        let p = OrientationMath.normalizedToPhysical(
            normalizedX: 0.25, normalizedY: 0.1, orientation: .portraitUpsideDown,
            logicalWidth: w, logicalHeight: h
        )
        assertClose(p, 0.75, 0.9, accuracy: 1e-9)
    }

    func testNormalizedToPhysicalGuardsDegenerateExtent() {
        // A zero-width logical extent cannot be renormalized; the input passes
        // through unchanged rather than producing NaN/Inf.
        let p = OrientationMath.normalizedToPhysical(
            normalizedX: 0.4, normalizedY: 0.6, orientation: .landscapeLeft,
            logicalWidth: 0, logicalHeight: 0
        )
        assertClose(p, 0.4, 0.6)
    }
}
