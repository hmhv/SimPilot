// TextInputEffectTests.swift
//
// Locks `type`'s effect check — the guard that stops a runtime which silently
// drops keyboard HID (iOS 27.0) from producing a green step over an empty field.
//
// The subtle half of the contract is what must NOT fail. The baseline is read
// AFTER the clear, because the two commonest idioms leave the field exactly as
// it started:
//
//   * `--clear` then the SAME string (the standard "put the field in a known
//     state" move)
//   * clearing a SecureField and retyping a password of the same length — its
//     value is a run of bullets either way
//
// Both are successful insertions. A pre-clear baseline would fail them.
//
// Driven through a scripted SimDriver: no simulator, no subprocess. The keyboard
// input method is used throughout because the paste path shells out to
// `simctl pbcopy`, which a unit test has no business doing.

import Foundation
import XCTest
import SimCore
@testable import sipi

private struct ScriptedDriverError: Error {}

/// A SimDriver that returns a prepared sequence of accessibility trees and
/// records the keystrokes it was handed. Every other capability is an
/// unimplemented no-op — this exists to exercise the text-entry policy, not the
/// driver.
private final class ScriptedDriver: SimDriver {
    /// Trees handed out in order; the last one repeats once exhausted, so a
    /// polling caller sees a stable end state instead of running out.
    private let trees: [[AXNode]]
    /// Zero-based read indices that throw instead of returning a tree. A SET
    /// models a transient stall as faithfully as a permanent one — pass
    /// `[1, 2]` for "fails twice then recovers", or every index for a bridge that
    /// never comes back.
    private let failingReads: Set<Int>
    private(set) var describeCount = 0
    private(set) var keystrokes = 0

    init(trees: [[AXNode]], failingReads: Set<Int> = []) {
        self.trees = trees.isEmpty ? [[]] : trees
        self.failingReads = failingReads
    }

    /// A driver whose reads all throw from `index` onward.
    static func failingFrom(_ index: Int, trees: [[AXNode]]) -> ScriptedDriver {
        ScriptedDriver(trees: trees, failingReads: Set(index..<(index + 500)))
    }

    func describe(_ udid: String, deep: Bool) throws -> [AXNode] {
        defer { describeCount += 1 }
        if failingReads.contains(describeCount) { throw ScriptedDriverError() }
        return trees[min(describeCount, trees.count - 1)]
    }

    func key(usage: Int, down: Bool, udid: String) throws { if down { keystrokes += 1 } }

    // Unused by the text-entry policy.
    func devices() throws -> [Device] { [] }
    func element(at point: Point, udid: String) throws -> AXNode? { nil }
    func setValue(_ value: String, at point: Point, udid: String) throws {}
    func tap(_ point: Point, udid: String) throws {}
    func touch(_ point: Point, phase: TouchPhase, udid: String) throws {}
    func swipe(_ a: Point, _ b: Point, duration: TimeInterval, udid: String) throws {}
    func longPress(_ point: Point, hold: TimeInterval, udid: String) throws {}
    func compositeDrag(from a: Point, to b: Point, duration: TimeInterval, steps: Int, udid: String) throws {}
    func button(_ button: HardwareButton, udid: String) throws {}
    func screenshot(to url: URL, udid: String) throws {}
    func uiOrientation(_ udid: String) throws -> UIOrientation { .portrait }
    func setOrientation(_ name: OrientationSetName, udid: String) throws {}
    func multiTouch(_ a: Point, _ b: Point, phase: TouchPhase, udid: String) throws {}
    func multiTouchSequence(_ frames: [MultiTouchFrame], frameDelay: TimeInterval, udid: String) throws {}
    func crown(delta: Double, udid: String) throws {}
}

final class TextInputEffectTests: XCTestCase {

    private func field(_ value: String?, type: String = "TextField") -> [AXNode] {
        [AXNode(AXValue: value, role: "AX" + type, type: type, AXUniqueId: "field.1", enabled: true)]
    }

    private func insert(
        _ text: String,
        clear: Bool = false,
        verifyEffect: Bool = true,
        trees: [[AXNode]],
        failingReads: Set<Int> = []
    ) throws -> ScriptedDriver {
        try insert(text, clear: clear, verifyEffect: verifyEffect,
                   driver: ScriptedDriver(trees: trees, failingReads: failingReads))
    }

    @discardableResult
    private func insert(
        _ text: String,
        clear: Bool = false,
        verifyEffect: Bool = true,
        driver: ScriptedDriver
    ) throws -> ScriptedDriver {
        try TextInput.insert(
            text,
            method: .keyboard,
            clear: clear,
            driver: driver,
            udid: "UDID",
            verifyEffect: verifyEffect
        )
        return driver
    }

    // MARK: - the cases that must pass

    func testPlainInsertionThatChangesTheFieldPasses() throws {
        let driver = try insert("hello", trees: [field(""), field("hello")])
        XCTAssertGreaterThan(driver.keystrokes, 0)
    }

    /// The regression this baseline placement exists for: clearing and retyping
    /// the same string leaves the field identical to how it started, but the
    /// insertion plainly happened.
    ///
    /// Tree order matches the reads the implementation makes: before the clear,
    /// after the clear (the baseline), then after the insertion.
    func testClearThenSameStringPasses() throws {
        XCTAssertNoThrow(
            try insert("same", clear: true, trees: [field("same"), field(""), field("same")])
        )
    }

    /// Same shape for a secure field: the value is bullets before and after, and
    /// a same-length password produces the same number of them.
    func testClearThenSameLengthSecureValuePasses() throws {
        XCTAssertNoThrow(
            try insert(
                "s3cret",
                clear: true,
                trees: [
                    field("••••••", type: "SecureTextField"),
                    field("", type: "SecureTextField"),
                    field("••••••", type: "SecureTextField")
                ]
            )
        )
    }

    /// The clear is asynchronous: the keystrokes return before the guest applies
    /// them, so the first read after them can still show the OLD value. Taking
    /// that as the baseline would make retyping the same string look unchanged.
    /// The baseline must wait for the field to move off its pre-clear value.
    func testStaleReadAfterClearDoesNotPoisonTheBaseline() throws {
        XCTAssertNoThrow(
            try insert(
                "same",
                clear: true,
                trees: [
                    field("same"),   // read 0: before the clear
                    field("same"),   // read 1: clear has not landed yet — must not become the baseline
                    field("same"),   // read 2: still stale
                    field(""),       // read 3: the clear lands; THIS is the baseline
                    field("same")    // read 4: the insertion
                ]
            )
        )
    }

    func testVerifyEffectOffSkipsTheCheckEntirely() throws {
        let driver = try insert("x", verifyEffect: false, trees: [[]])
        // No tree reads at all when the check is off.
        XCTAssertEqual(driver.describeCount, 0)
    }

    /// Emptying a field asks the CLEAR to be the whole effect, so the baseline
    /// must precede it. Reading after would compare an emptied field against
    /// itself and fail every successful clear.
    func testEmptyTextWithClearPassesWhenTheFieldEmpties() throws {
        XCTAssertNoThrow(
            try insert("", clear: true, trees: [field("old"), field("")])
        )
    }

    /// The same path still catches a clear that did nothing.
    func testEmptyTextWithClearFailsWhenTheFieldKeepsItsValue() {
        XCTAssertThrowsError(try insert("", clear: true, trees: [field("old"), field("old")])) { error in
            let message = (error as? TextInputError)?.description ?? "\(error)"
            // Names the clear, not the insertion — the insertion was never the subject.
            XCTAssertTrue(message.contains("clear had no effect"), message)
        }
    }

    // MARK: - the cases that must fail

    /// A runtime that drops keystrokes leaves the field untouched. This is the
    /// failure the whole check exists to surface.
    func testUnchangedFieldFails() {
        XCTAssertThrowsError(try insert("hello", trees: [field("old")])) { error in
            let message = (error as? TextInputError)?.description ?? "\(error)"
            XCTAssertTrue(message.contains("did not change"), message)
        }
    }

    func testNoTextEntryElementFails() {
        let label = [AXNode(AXLabel: "Not a field", role: "AXStaticText", type: "StaticText", enabled: true)]
        XCTAssertThrowsError(try insert("hello", trees: [label])) { error in
            let message = (error as? TextInputError)?.description ?? "\(error)"
            XCTAssertTrue(message.contains("no text field is on screen"), message)
        }
    }

    /// A cleared field that stays cleared means the insertion did nothing, even
    /// though the clear itself worked.
    func testClearThatIsNotFollowedByInsertionFails() {
        XCTAssertThrowsError(try insert("hello", clear: true, trees: [field(""), field("")])) { error in
            let message = (error as? TextInputError)?.description ?? "\(error)"
            XCTAssertTrue(message.contains("did not change"), message)
        }
    }

    /// The worst case the check must not wave through: the runtime drops the
    /// keystrokes AND the accessibility bridge stalls, so nothing can be read back.
    /// Treating an unreadable tree as success would report green having entered
    /// nothing — on the very device where that happens (iOS 27).
    func testUnreadableTreeAfterInsertionIsReportedAsUnverifiable() {
        // The baseline read succeeds; every read after it throws.
        XCTAssertThrowsError(
            try insert("hello", driver: .failingFrom(1, trees: [field("")]))
        ) { error in
            let message = (error as? TextInputError)?.description ?? "\(error)"
            XCTAssertTrue(message.contains("could not verify"), message)
            // Points at the known recovery rather than blaming the app...
            XCTAssertTrue(message.contains("voiceover"), message)
            // ...and warns that the text WAS sent, so a blind retry double-types.
            XCTAssertTrue(message.contains("twice"), message)
        }
    }

    /// A stall that clears mid-poll must not fail a step whose insertion landed.
    /// Reads 1 and 2 (the first two verification polls) throw; read 3 sees the
    /// inserted value.
    func testTransientReadFailureThatRecoversStillPasses() throws {
        let driver = ScriptedDriver(
            trees: [field(""), field(""), field(""), field("hello")],
            failingReads: [1, 2]
        )
        XCTAssertNoThrow(try insert("hello", driver: driver))
        XCTAssertGreaterThan(driver.describeCount, 3, "the check must have polled past the failures")
    }

    /// Nothing is typed when the baseline cannot be read, so a retry is safe —
    /// the failure names that explicitly. Reporting it after the insertion would
    /// make a retried step enter the text twice.
    func testUnreadableBaselineFailsBeforeTypingAnything() {
        XCTAssertThrowsError(
            try insert("hello", driver: .failingFrom(0, trees: [field("")]))
        ) { error in
            let message = (error as? TextInputError)?.description ?? "\(error)"
            XCTAssertTrue(message.contains("not attempted"), message)
            XCTAssertTrue(message.contains("safe to retry"), message)
        }
    }

    func testUnreadableBaselineSendsNoKeystrokes() {
        let driver = ScriptedDriver.failingFrom(0, trees: [field("")])
        XCTAssertThrowsError(try insert("hello", driver: driver))
        XCTAssertEqual(driver.keystrokes, 0, "no text may be sent when the baseline is unknown")
    }

    /// A field that disappears — the keyboard dismissed, a sheet closed — is a
    /// change, not a failed read. It must not be reported as unverifiable.
    func testFieldDisappearingAfterInsertionPasses() throws {
        let noField = [AXNode(AXLabel: "Done", role: "AXStaticText", type: "StaticText", enabled: true)]
        XCTAssertNoThrow(try insert("hello", trees: [field(""), noField]))
    }

    /// A stale first read (the field has not caught up yet) followed by a dead
    /// bridge must report "could not verify", not "nothing arrived" — the final
    /// state was never observed.
    func testStaleReadFollowedByDeadBridgeIsUnverifiable() {
        // Read 0 = baseline. Read 1 returns the still-unchanged field, then the
        // bridge dies for good.
        let driver = ScriptedDriver(
            trees: [field("old"), field("old")],
            failingReads: Set(2..<500)
        )
        XCTAssertThrowsError(try insert("hello", driver: driver)) { error in
            let message = (error as? TextInputError)?.description ?? "\(error)"
            XCTAssertTrue(message.contains("could not verify"), message)
            XCTAssertFalse(message.contains("did not change"), message)
        }
    }

    // MARK: - retry advice

    /// The harness retries a failed step by re-running the whole action. That is
    /// right for a failure that happened before anything reached the device and
    /// wrong once text is in flight, so the errors carry the distinction. These
    /// lock which failures say which.
    func testUnverifiableFailureIsMarkedUnsafeToRetry() {
        XCTAssertThrowsError(
            try insert("hello", driver: .failingFrom(1, trees: [field("")]))
        ) { error in
            XCTAssertEqual((error as? TextInputError)?.retrySafe, false,
                           "a sent-but-unverified insertion must not be retried automatically")
        }
    }

    func testPreSendFailuresAreSafeToRetry() {
        // Nothing reached the device in any of these.
        let cases: [(String, () throws -> Void)] = [
            ("unreadable baseline", { _ = try self.insert("hello", driver: .failingFrom(0, trees: [self.field("")])) }),
            ("no text field", {
                let label = [AXNode(AXLabel: "x", role: "AXStaticText", type: "StaticText", enabled: true)]
                _ = try self.insert("hello", trees: [label])
            }),
            ("unrepresentable text", { _ = try self.insert("こんにちは", trees: [self.field("")]) })
        ]
        for (name, body) in cases {
            XCTAssertThrowsError(try body(), name) { error in
                XCTAssertEqual((error as? TextInputError)?.retrySafe, true, name)
            }
        }
    }

    /// A field that stayed put was not modified, so re-running is safe — the
    /// retry will simply fail the same way until the cause is fixed.
    func testUnchangedFieldIsSafeToRetry() {
        XCTAssertThrowsError(try insert("hello", trees: [field("old")])) { error in
            XCTAssertEqual((error as? TextInputError)?.retrySafe, true)
        }
    }

    /// Keyboard mode rejects text it cannot type rather than sending the wrong
    /// characters — and does so before touching the device.
    func testNonUSTextIsRejectedInKeyboardMode() {
        XCTAssertThrowsError(try insert("こんにちは", trees: [field("")])) { error in
            let message = (error as? TextInputError)?.description ?? "\(error)"
            XCTAssertTrue(message.contains("non-US-keyboard"), message)
        }
    }
}
