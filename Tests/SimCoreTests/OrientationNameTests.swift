// OrientationNameTests.swift
//
// Locks the pure-logic orientation-name mapping for the orientation SET path:
// name parsing (with the short aliases), native-expressibility (PurpleEvent
// covers 1...4 only), the canonical name handed to the native SET, and the
// Simulator "Device > Orientation" menu item label used by the osascript
// fallback. Pure Foundation — no simulator.

import XCTest
@testable import SimCore

final class OrientationNameTests: XCTestCase {

    func testCanonicalNamesParse() {
        XCTAssertEqual(OrientationSetName("portrait"), .portrait)
        XCTAssertEqual(OrientationSetName("portrait-upside-down"), .portraitUpsideDown)
        XCTAssertEqual(OrientationSetName("landscape-left"), .landscapeLeft)
        XCTAssertEqual(OrientationSetName("landscape-right"), .landscapeRight)
        XCTAssertEqual(OrientationSetName("face-up"), .faceUp)
        XCTAssertEqual(OrientationSetName("face-down"), .faceDown)
    }

    func testAliasesParse() {
        // Short aliases the CLI accepts.
        XCTAssertEqual(OrientationSetName("left"), .landscapeLeft)
        XCTAssertEqual(OrientationSetName("right"), .landscapeRight)
        XCTAssertEqual(OrientationSetName("landscape"), .landscapeRight)
        XCTAssertEqual(OrientationSetName("upside-down"), .portraitUpsideDown)
    }

    func testUnderscoreAndCaseAreNormalized() {
        XCTAssertEqual(OrientationSetName("LANDSCAPE_LEFT"), .landscapeLeft)
        XCTAssertEqual(OrientationSetName("Face_Up"), .faceUp)
        XCTAssertEqual(OrientationSetName("Portrait"), .portrait)
    }

    func testUnknownNameIsNil() {
        XCTAssertNil(OrientationSetName("sideways"))
        XCTAssertNil(OrientationSetName(""))
        XCTAssertNil(OrientationSetName("flat"))
    }

    func testNativeExpressibility() {
        // PurpleEvent covers UIDeviceOrientation 1...4; face-up/face-down do not.
        XCTAssertTrue(OrientationSetName.portrait.isNativeExpressible)
        XCTAssertTrue(OrientationSetName.portraitUpsideDown.isNativeExpressible)
        XCTAssertTrue(OrientationSetName.landscapeLeft.isNativeExpressible)
        XCTAssertTrue(OrientationSetName.landscapeRight.isNativeExpressible)
        XCTAssertFalse(OrientationSetName.faceUp.isNativeExpressible)
        XCTAssertFalse(OrientationSetName.faceDown.isNativeExpressible)
    }

    func testCanonicalNameForNativeSet() {
        // The native SET / READ share these lowercase names.
        XCTAssertEqual(OrientationSetName.portrait.canonicalName, "portrait")
        XCTAssertEqual(OrientationSetName.portraitUpsideDown.canonicalName, "portrait-upside-down")
        XCTAssertEqual(OrientationSetName.landscapeLeft.canonicalName, "landscape-left")
        XCTAssertEqual(OrientationSetName.landscapeRight.canonicalName, "landscape-right")
    }

    func testMenuItemNamesMatchSimulatorMenu() {
        // These must match the Simulator "Device > Orientation" submenu labels the
        // osascript fallback clicks.
        XCTAssertEqual(OrientationSetName.portrait.menuItemName, "Portrait")
        XCTAssertEqual(OrientationSetName.portraitUpsideDown.menuItemName, "Portrait Upside Down")
        XCTAssertEqual(OrientationSetName.landscapeLeft.menuItemName, "Landscape Left")
        XCTAssertEqual(OrientationSetName.landscapeRight.menuItemName, "Landscape Right")
        XCTAssertEqual(OrientationSetName.faceUp.menuItemName, "Face Up")
        XCTAssertEqual(OrientationSetName.faceDown.menuItemName, "Face Down")
    }

    // MARK: - multitouch coordinate-unit conversion

    func testMultiTouchNormalizedPointsPassThrough() throws {
        // multitouch reuses the shared CoordinateConverter, so a --norm pair is
        // validated and passed through for both fingers.
        let a = try CoordinateConverter.normalize(x: 0.3, y: 0.4, unit: .norm, screen: nil)
        let b = try CoordinateConverter.normalize(x: 0.7, y: 0.6, unit: .norm, screen: nil)
        XCTAssertEqual(a, Point(x: 0.3, y: 0.4))
        XCTAssertEqual(b, Point(x: 0.7, y: 0.6))
    }

    func testMultiTouchPixelPointsConvertWithScreenSize() throws {
        // A pinch given in pixels converts each finger with the screen size.
        let screen = ScreenSize(width: 400, height: 800)
        let a = try CoordinateConverter.normalize(x: 100, y: 200, unit: .pixel, screen: screen)
        let b = try CoordinateConverter.normalize(x: 300, y: 600, unit: .pixel, screen: screen)
        XCTAssertEqual(a.x, 0.25, accuracy: 1e-9)
        XCTAssertEqual(a.y, 0.25, accuracy: 1e-9)
        XCTAssertEqual(b.x, 0.75, accuracy: 1e-9)
        XCTAssertEqual(b.y, 0.75, accuracy: 1e-9)
    }
}
