// InputParityTests.swift
//
// Locks the input logic that lives in SimCore: coordinate-unit standardization,
// key-combo LIFO ordering, gesture-preset geometry, and slider drag planning.
// All pure functions — no simulator required.

import XCTest
@testable import SimCore

final class InputParityTests: XCTestCase {

    // MARK: - Gate 4: coordinate units

    func testNormPassesNormalizedThrough() throws {
        let p = try CoordinateConverter.normalize(x: 0.25, y: 0.75, unit: .norm, screen: nil)
        XCTAssertEqual(p.x, 0.25, accuracy: 1e-9)
        XCTAssertEqual(p.y, 0.75, accuracy: 1e-9)
    }

    func testNormRejectsOutOfRange() {
        // A pixel value (e.g. 100) handed to --norm must be rejected, not silently
        // treated as a top-left tap.
        XCTAssertThrowsError(try CoordinateConverter.normalize(x: 100, y: 0.5, unit: .norm, screen: nil)) { error in
            guard case CoordinateError.normalizedOutOfRange(let axis, _) = error else {
                return XCTFail("expected normalizedOutOfRange, got \(error)")
            }
            XCTAssertEqual(axis, "x")
        }
    }

    func testPixelConvertsWithScreenSize() throws {
        let screen = ScreenSize(width: 390, height: 844)
        let p = try CoordinateConverter.normalize(x: 195, y: 422, unit: .pixel, screen: screen)
        XCTAssertEqual(p.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(p.y, 0.5, accuracy: 1e-9)
    }

    func testPixelRequiresScreenSize() {
        XCTAssertThrowsError(try CoordinateConverter.normalize(x: 10, y: 10, unit: .pixel, screen: nil)) { error in
            guard case CoordinateError.missingScreenSize = error else {
                return XCTFail("expected missingScreenSize, got \(error)")
            }
        }
    }

    func testPixelOutsideScreenIsRejected() {
        let screen = ScreenSize(width: 390, height: 844)
        XCTAssertThrowsError(try CoordinateConverter.normalize(x: 500, y: 10, unit: .pixel, screen: screen)) { error in
            guard case CoordinateError.pixelOutOfBounds(let axis, _, _) = error else {
                return XCTFail("expected pixelOutOfBounds, got \(error)")
            }
            XCTAssertEqual(axis, "x")
        }
    }

    func testPixelNegativeIsRejected() {
        let screen = ScreenSize(width: 390, height: 844)
        XCTAssertThrowsError(try CoordinateConverter.normalize(x: -1, y: 10, unit: .pixel, screen: screen)) { error in
            guard case CoordinateError.negativePixel = error else {
                return XCTFail("expected negativePixel, got \(error)")
            }
        }
    }

    // MARK: - Key input

    func testKeyPressIsDownThenUp() {
        XCTAssertEqual(KeyInput.keyPress(usage: 40), [
            HIDKeyEvent(usage: 40, down: true),
            HIDKeyEvent(usage: 40, down: false)
        ])
    }

    func testKeySequencePressesEachInOrder() {
        XCTAssertEqual(KeyInput.keySequence(usages: [11, 8]), [
            HIDKeyEvent(usage: 11, down: true),
            HIDKeyEvent(usage: 11, down: false),
            HIDKeyEvent(usage: 8, down: true),
            HIDKeyEvent(usage: 8, down: false)
        ])
    }

    func testKeyComboReleasesModifiersLIFO() {
        // Cmd(227)+Shift(225)+A(4): hold in order, press A, release in reverse.
        XCTAssertEqual(KeyInput.keyCombo(modifiers: [227, 225], key: 4), [
            HIDKeyEvent(usage: 227, down: true),
            HIDKeyEvent(usage: 225, down: true),
            HIDKeyEvent(usage: 4, down: true),
            HIDKeyEvent(usage: 4, down: false),
            HIDKeyEvent(usage: 225, down: false),
            HIDKeyEvent(usage: 227, down: false)
        ])
    }

    func testPasteComboIsCmdV() {
        XCTAssertEqual(KeyInput.pasteCombo(), [
            HIDKeyEvent(usage: KeyInput.leftCommandUsage, down: true),
            HIDKeyEvent(usage: KeyInput.vUsage, down: true),
            HIDKeyEvent(usage: KeyInput.vUsage, down: false),
            HIDKeyEvent(usage: KeyInput.leftCommandUsage, down: false)
        ])
    }

    // MARK: - Gesture presets

    func testScrollDownStartsAboveCenterEndsBelow() {
        let (start, end) = GesturePreset.scrollDown.normalizedEndpoints()
        XCTAssertEqual(start.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(end.x, 0.5, accuracy: 1e-9)
        XCTAssertLessThan(start.y, end.y, "scroll-down finger moves downward")
        // Endpoints stay within the screen.
        for p in [start, end] {
            XCTAssertGreaterThanOrEqual(p.y, 0)
            XCTAssertLessThanOrEqual(p.y, 1)
        }
    }

    func testScrollUpIsTheInverseOfScrollDown() {
        let down = GesturePreset.scrollDown.normalizedEndpoints()
        let up = GesturePreset.scrollUp.normalizedEndpoints()
        XCTAssertEqual(up.start.y, down.end.y, accuracy: 1e-9)
        XCTAssertEqual(up.end.y, down.start.y, accuracy: 1e-9)
    }

    func testSwipeFromLeftEdgeStartsNearLeft() {
        let (start, end) = GesturePreset.swipeFromLeftEdge.normalizedEndpoints()
        XCTAssertLessThan(start.x, 0.1, "starts near the left edge")
        XCTAssertGreaterThan(end.x, 0.9, "ends near the right edge")
        XCTAssertEqual(start.y, 0.5, accuracy: 1e-9)
    }

    func testEdgeSwipeDefaultDurationIsShorterThanScroll() {
        XCTAssertEqual(GesturePreset.scrollUp.defaultDuration, 0.5, accuracy: 1e-9)
        XCTAssertEqual(GesturePreset.swipeFromLeftEdge.defaultDuration, 0.3, accuracy: 1e-9)
    }

    func testAllGesturePresetsResolveInBounds() {
        for preset in GesturePreset.allCases {
            let (start, end) = preset.normalizedEndpoints()
            for p in [start, end] {
                XCTAssertGreaterThanOrEqual(p.x, 0, "\(preset) start/end x in bounds")
                XCTAssertLessThanOrEqual(p.x, 1, "\(preset) start/end x in bounds")
                XCTAssertGreaterThanOrEqual(p.y, 0, "\(preset) start/end y in bounds")
                XCTAssertLessThanOrEqual(p.y, 1, "\(preset) start/end y in bounds")
            }
        }
    }

    // MARK: - Slider planning

    private func slider(value: String, x: Double = 20, width: Double = 300) -> AXNode {
        AXNode(
            AXValue: value,
            role_description: "slider",
            role: "AXSlider",
            type: "Slider",
            AXUniqueId: "brightness",
            enabled: true,
            frame: AXNode.Frame(x: x, y: 400, width: width, height: 30)
        )
    }

    private func appFrame() -> AXNode.Frame {
        AXNode.Frame(x: 0, y: 0, width: 390, height: 844)
    }

    func testSliderPlanDragsTowardHigherTarget() throws {
        // Current 0.2 (20%), target 0.8 (80%): end must be to the right of start.
        let plan = try SliderPlan.makeDragPlan(
            element: slider(value: "0.2"),
            applicationFrame: appFrame(),
            targetNormalized: 0.8
        )
        XCTAssertEqual(plan.currentNormalized, 0.2, accuracy: 1e-9)
        XCTAssertEqual(plan.targetNormalized, 0.8, accuracy: 1e-9)
        XCTAssertGreaterThan(plan.logicalEnd.x, plan.logicalStart.x)
        XCTAssertFalse(plan.alreadyAtTarget)
        // Commanded value overshoots the target by the high-range offset.
        XCTAssertEqual(plan.commandedNormalized, 0.8 + SliderPlan.highRangeCoordinateOffset, accuracy: 1e-9)
    }

    func testSliderPlanDragsTowardLowerTarget() throws {
        let plan = try SliderPlan.makeDragPlan(
            element: slider(value: "80%"),
            applicationFrame: appFrame(),
            targetNormalized: 0.2
        )
        XCTAssertEqual(plan.currentNormalized, 0.8, accuracy: 1e-9)
        XCTAssertLessThan(plan.logicalEnd.x, plan.logicalStart.x)
        XCTAssertEqual(plan.commandedNormalized, 0.2 - SliderPlan.lowRangeCoordinateOffset, accuracy: 1e-9)
    }

    func testSliderAlreadyAtTargetWithinTolerance() throws {
        let plan = try SliderPlan.makeDragPlan(
            element: slider(value: "0.5"),
            applicationFrame: appFrame(),
            targetNormalized: 0.5
        )
        XCTAssertTrue(plan.alreadyAtTarget)
        // No movement when already at target (commanded == current).
        XCTAssertEqual(plan.commandedNormalized, plan.currentNormalized, accuracy: 1e-9)
    }

    func testSliderEndXClampedToApplicationFrame() throws {
        // A slider that spans most of the screen, dragged to max: end-X must stay
        // within the application frame.
        let plan = try SliderPlan.makeDragPlan(
            element: slider(value: "0.0", x: 20, width: 360),
            applicationFrame: appFrame(),
            targetNormalized: 1.0
        )
        XCTAssertLessThanOrEqual(plan.logicalEnd.x, appFrame().x + appFrame().width)
    }

    func testSliderRejectsNonSlider() {
        let button = AXNode(
            AXLabel: "Go",
            role: "AXButton",
            type: "Button",
            frame: AXNode.Frame(x: 0, y: 0, width: 100, height: 44)
        )
        XCTAssertThrowsError(try SliderPlan.makeDragPlan(element: button, applicationFrame: appFrame(), targetNormalized: 0.5)) { error in
            guard case SliderPlan.SliderError.notASlider = error else {
                return XCTFail("expected notASlider, got \(error)")
            }
        }
    }

    func testSliderRejectsNonNumericValue() {
        XCTAssertThrowsError(try SliderPlan.makeDragPlan(element: slider(value: "loud"), applicationFrame: appFrame(), targetNormalized: 0.5)) { error in
            guard case SliderPlan.SliderError.nonNumericValue = error else {
                return XCTFail("expected nonNumericValue, got \(error)")
            }
        }
    }

    func testSliderValueParsingForms() throws {
        XCTAssertEqual(try SliderPlan.parseNormalizedAXValue("0.5"), 0.5, accuracy: 1e-9)
        XCTAssertEqual(try SliderPlan.parseNormalizedAXValue("50%"), 0.5, accuracy: 1e-9)
        XCTAssertEqual(try SliderPlan.parseNormalizedAXValue("50"), 0.5, accuracy: 1e-9)
        XCTAssertEqual(try SliderPlan.parseNormalizedAXValue(" 0.25 "), 0.25, accuracy: 1e-9)
    }

    func testSliderToleranceDefaultIsTwoPercent() {
        XCTAssertEqual(SliderPlan.valueTolerance, 0.02, accuracy: 1e-9)
        XCTAssertTrue(SliderPlan.isWithinTolerance(observed: 0.49, target: 0.5))
        XCTAssertFalse(SliderPlan.isWithinTolerance(observed: 0.45, target: 0.5))
    }
}
