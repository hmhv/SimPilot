// PinchPlanTests.swift
//
// Locks the pinch geometry: the fingers must travel along one axis through a
// fixed center, the endpoints must respect the minimum separation, and a center
// near an edge must shorten the gesture rather than push a contact off screen.

import XCTest
@testable import SimCore

final class PinchPlanTests: XCTestCase {

    private let center = Point(x: 0.5, y: 0.5)

    func testPinchOutStartsNarrowAndEndsWide() throws {
        let plan = try PinchPlan.make(center: center, separation: 0.4, direction: .pinchOut, steps: 10)
        let first = try XCTUnwrap(plan.frames.first)
        let last = try XCTUnwrap(plan.frames.last)
        XCTAssertEqual(gap(first), PinchPlan.minimumSeparation, accuracy: 1e-9)
        XCTAssertEqual(gap(last), 0.4, accuracy: 1e-9)
    }

    func testPinchInStartsWideAndEndsNarrow() throws {
        let plan = try PinchPlan.make(center: center, separation: 0.4, direction: .pinchIn, steps: 10)
        let first = try XCTUnwrap(plan.frames.first)
        let last = try XCTUnwrap(plan.frames.last)
        XCTAssertEqual(gap(first), 0.4, accuracy: 1e-9)
        XCTAssertEqual(gap(last), PinchPlan.minimumSeparation, accuracy: 1e-9)
    }

    func testFrameSequenceIsBeginThenMovesThenEnd() throws {
        let plan = try PinchPlan.make(center: center, separation: 0.4, direction: .pinchOut, steps: 5)
        // 1 touch-down + 5 moves + 1 lift.
        XCTAssertEqual(plan.frames.count, 7)
        XCTAssertEqual(plan.frames.first?.phase, .begin)
        XCTAssertEqual(plan.frames.last?.phase, .end)
        XCTAssertTrue(plan.frames.dropLast().allSatisfy { $0.phase == .begin })
    }

    /// The center must not drift: a moving midpoint reads as a two-finger pan
    /// rather than a pinch.
    func testCenterStaysFixedAcrossEveryFrame() throws {
        let plan = try PinchPlan.make(
            center: Point(x: 0.3, y: 0.6), separation: 0.3, direction: .pinchIn, steps: 8)
        for frame in plan.frames {
            XCTAssertEqual((frame.a.y + frame.b.y) / 2, 0.6, accuracy: 1e-9)
            XCTAssertEqual(frame.a.x, 0.3, accuracy: 1e-9)
            XCTAssertEqual(frame.b.x, 0.3, accuracy: 1e-9)
        }
    }

    func testEveryContactStaysOnScreen() throws {
        for centerY in [0.08, 0.2, 0.5, 0.8, 0.94] {
            let plan = try PinchPlan.make(
                center: Point(x: 0.5, y: centerY), separation: 0.9, direction: .pinchOut, steps: 6)
            for frame in plan.frames {
                XCTAssertTrue((0.0...1.0).contains(frame.a.y), "a off screen at centerY \(centerY): \(frame.a.y)")
                XCTAssertTrue((0.0...1.0).contains(frame.b.y), "b off screen at centerY \(centerY): \(frame.b.y)")
            }
        }
    }

    /// A center close to the edge shrinks the travel instead of failing or
    /// sliding the center — but only down to the point where a pinch is still
    /// distinguishable from a two-finger tap.
    func testCenterTooCloseToEdgeThrows() {
        XCTAssertThrowsError(
            try PinchPlan.make(center: Point(x: 0.5, y: 0.01), separation: 0.4, direction: .pinchOut, steps: 5)
        )
    }

    func testRejectsSeparationAtOrBelowMinimum() {
        XCTAssertThrowsError(
            try PinchPlan.make(center: center, separation: PinchPlan.minimumSeparation, direction: .pinchOut, steps: 5)
        )
    }

    func testRejectsOutOfRangeCenter() {
        XCTAssertThrowsError(
            try PinchPlan.make(center: Point(x: 1.5, y: 0.5), separation: 0.4, direction: .pinchOut, steps: 5)
        )
    }

    func testRejectsOutOfRangeSteps() {
        XCTAssertThrowsError(
            try PinchPlan.make(center: center, separation: 0.4, direction: .pinchOut, steps: 0))
        XCTAssertThrowsError(
            try PinchPlan.make(center: center, separation: 0.4, direction: .pinchOut, steps: 201))
    }

    func testFrameDelaySpreadsDurationOverMoves() {
        XCTAssertEqual(PinchPlan.frameDelay(duration: 1.0, steps: 20), 0.05, accuracy: 1e-9)
        XCTAssertEqual(PinchPlan.frameDelay(duration: 0, steps: 20), 0)
        XCTAssertEqual(PinchPlan.frameDelay(duration: 1.0, steps: 0), 0)
    }

    private func gap(_ frame: PinchPlan.Frame) -> Double {
        abs(frame.b.y - frame.a.y)
    }
}
