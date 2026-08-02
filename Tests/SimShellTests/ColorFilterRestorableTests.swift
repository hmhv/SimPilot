// ColorFilterRestorableTests.swift
//
// Locks `AppearanceState.colorFilterRestoreBlocker`, the predicate the harness
// uses to refuse a `display-state` write it could not undo.
//
// Two regressions this guards, in opposite directions:
//
//  - Too permissive: the kind/intensity pair is exempt from the harness's "did
//    the runtime report this facet?" check, on the reasoning that switching the
//    filter back off restores the screen. That only holds when the baseline had
//    the filter OFF. With it ON and a baseline value that cannot be written
//    back, the restore silently omits it and the filter returns at the RUN's
//    value — a visibly wrong screen reported as a clean run.
//  - Too strict: restorability depends on what the run CHANGES. A run that only
//    toggles the filter never overwrites the stored kind or intensity, so an
//    unrestorable-looking baseline is irrelevant and the run must not be
//    refused.

import XCTest
@testable import SimShell

final class ColorFilterRestorableTests: XCTestCase {

    private func state(
        enabled: Bool?,
        type: String? = nil,
        intensity: Double? = nil
    ) -> AppearanceState {
        AppearanceState(
            colorFilterEnabled: enabled,
            colorFilterType: type,
            colorFilterIntensity: intensity
        )
    }

    // MARK: - Filter off: nothing to put back

    func testFilterOffIsAlwaysRestorable() {
        for (type, intensity) in [(nil, nil), ("deuteranopia", 0.1), ("grayscale", nil)] as [(String?, Double?)] {
            XCTAssertNil(
                state(enabled: false, type: type, intensity: intensity)
                    .colorFilterRestoreBlocker(changingType: true, changingIntensity: true),
                "switching the filter off restores the screen, whatever is configured behind it"
            )
        }
    }

    func testUnreportedFilterIsRestorable() {
        XCTAssertNil(
            state(enabled: nil).colorFilterRestoreBlocker(changingType: true, changingIntensity: true),
            "a runtime that does not report the filter is handled by the reported-facet check"
        )
    }

    // MARK: - A facet the run does not change needs nothing from the restore

    func testOutOfRangeIntensityIsIrrelevantWhenTheRunDoesNotChangeIt() {
        XCTAssertNil(
            state(enabled: true, type: "deuteranopia", intensity: 0.1)
                .colorFilterRestoreBlocker(changingType: false, changingIntensity: false),
            "a run that only toggles the filter leaves the stored intensity exactly as it found it"
        )
    }

    func testMissingIntensityIsIrrelevantWhenOnlyTheTypeChanges() {
        XCTAssertNil(
            state(enabled: true, type: "deuteranopia")
                .colorFilterRestoreBlocker(changingType: true, changingIntensity: false)
        )
    }

    func testMissingTypeIsIrrelevantWhenOnlyTheIntensityChanges() {
        XCTAssertNil(
            state(enabled: true, intensity: 0.5)
                .colorFilterRestoreBlocker(changingType: false, changingIntensity: true)
        )
    }

    // MARK: - Changing a facet the baseline cannot give back

    func testChangingIntensityWithNoBaselineIntensityIsBlocked() {
        let blocker = state(enabled: true, type: "deuteranopia")
            .colorFilterRestoreBlocker(changingType: false, changingIntensity: true)
        XCTAssertNotNil(blocker, "there is no original intensity to write back")
        XCTAssertTrue(blocker?.contains("does not report the current colour-filter intensity") == true,
                      "\(blocker ?? "nil")")
    }

    func testChangingTypeWithNoBaselineTypeIsBlocked() {
        let blocker = state(enabled: true, intensity: 0.5)
            .colorFilterRestoreBlocker(changingType: true, changingIntensity: false)
        XCTAssertTrue(blocker?.contains("does not report the current colour-filter type") == true,
                      "\(blocker ?? "nil")")
    }

    // MARK: - Each blocker states its own consequence
    //
    // They genuinely differ, and a generic "the screen would keep this test's
    // setting" was wrong for grayscale.

    func testGrayscaleBlockerSaysTheScreenComesBackAndOnlyStorageLeaks() {
        let blocker = state(enabled: true, type: "grayscale", intensity: 0.5)
            .colorFilterRestoreBlocker(changingType: false, changingIntensity: true)
        XCTAssertTrue(blocker?.contains("return to grayscale") == true,
                      "the kind IS restorable here: \(blocker ?? "nil")")
        XCTAssertTrue(blocker?.contains("stored settings") == true,
                      "what leaks is the stored intensity: \(blocker ?? "nil")")
    }

    func testOutOfRangeBlockerSaysTheFilterComesBackAtTheRunsIntensity() {
        let blocker = state(enabled: true, type: "deuteranopia", intensity: 0.1)
            .colorFilterRestoreBlocker(changingType: false, changingIntensity: true)
        XCTAssertTrue(blocker?.contains("at the run's intensity") == true, "\(blocker ?? "nil")")
    }

    /// Grayscale decides the consequence, so it must be checked before the
    /// missing/out-of-range rules — they would otherwise answer for it and claim
    /// the screen stays wrong, when grayscale comes back looking correct.
    func testGrayscaleWinsOverAMissingIntensity() {
        let blocker = state(enabled: true, type: "grayscale", intensity: nil)
            .colorFilterRestoreBlocker(changingType: false, changingIntensity: true)
        XCTAssertTrue(blocker?.contains("return to grayscale") == true, "\(blocker ?? "nil")")
        XCTAssertFalse(blocker?.contains("would not go back") == true, "\(blocker ?? "nil")")
    }

    func testGrayscaleWinsOverAnOutOfRangeIntensity() {
        let blocker = state(enabled: true, type: "grayscale", intensity: 0.1)
            .colorFilterRestoreBlocker(changingType: false, changingIntensity: true)
        XCTAssertTrue(blocker?.contains("return to grayscale") == true, "\(blocker ?? "nil")")
        XCTAssertFalse(blocker?.contains("at the run's intensity") == true, "\(blocker ?? "nil")")
    }

    func testChangingIntensityWithAnOutOfRangeBaselineIsBlocked() {
        for intensity in [0.0, 0.1, 0.24, 1.5] {
            let blocker = state(enabled: true, type: "deuteranopia", intensity: intensity)
                .colorFilterRestoreBlocker(changingType: false, changingIntensity: true)
            XCTAssertNotNil(blocker, "intensity \(intensity) cannot be written back")
            XCTAssertTrue(blocker?.contains("outside the 0.25...1.0 range") == true, "\(blocker ?? "nil")")
        }
    }

    func testChangingIntensityAgainstAGrayscaleBaselineIsBlocked() {
        let blocker = state(enabled: true, type: "grayscale", intensity: 0.5)
            .colorFilterRestoreBlocker(changingType: false, changingIntensity: true)
        XCTAssertTrue(blocker?.contains("grayscale") == true, "\(blocker ?? "nil")")
    }

    func testChangingIntensityWithAnInRangeBaselineIsAllowed() {
        for intensity in [0.25, 0.8, 1.0] {
            XCTAssertNil(
                state(enabled: true, type: "deuteranopia", intensity: intensity)
                    .colorFilterRestoreBlocker(changingType: true, changingIntensity: true),
                "intensity \(intensity) is inside the range devicectl accepts"
            )
        }
    }
}
