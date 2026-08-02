// OptionalStepSkipTests.swift
//
// Locks the rule that decides when an `optional` step becomes a passing skip.
//
// The regression this guards: the decision used to wrap the whole lookup in a
// bare `catch { return false }`, so an ambiguous selector or an unreadable
// accessibility tree was recorded as `passed: true, skipped: true` — a real
// defect reported as a green step. Only a genuine not-found in BOTH trees may
// skip. Everything else must fall through to normal execution and let that
// decide the outcome — which is not the same as "it fails": a transient read
// error can still pass on the step's own attempt.
//
// No simulator involved: the tree probe is a closure.

import XCTest
@testable import SimCore
@testable import sipi

final class OptionalStepSkipTests: XCTestCase {

    private struct TreeUnreadable: Error {}

    // MARK: - The one case that may skip

    func testAbsentFromBothTreesIsSkippable() {
        XCTAssertTrue(
            OptionalStepSkip.targetIsDefinitelyAbsent { _ in false },
            "not found in the fast tree nor the deep tree is the definition of absent"
        )
    }

    // MARK: - Present anywhere is not absent

    func testFoundInFastTreeIsNotAbsent() {
        XCTAssertFalse(OptionalStepSkip.targetIsDefinitelyAbsent { _ in true })
    }

    func testFoundOnlyInDeepTreeIsNotAbsent() {
        XCTAssertFalse(
            OptionalStepSkip.targetIsDefinitelyAbsent { deep in deep },
            "missing from the fast tree only means look deeper"
        )
    }

    func testDeepTreeIsNotProbedWhenTheFastTreeAlreadyMatched() {
        var probed: [Bool] = []
        _ = OptionalStepSkip.targetIsDefinitelyAbsent { deep in
            probed.append(deep)
            return true
        }
        XCTAssertEqual(probed, [false], "a fast-tree hit must not pay for the deep pass")
    }

    func testBothTreesAreProbedWhenTheFastTreeMisses() {
        var probed: [Bool] = []
        _ = OptionalStepSkip.targetIsDefinitelyAbsent { deep in
            probed.append(deep)
            return false
        }
        XCTAssertEqual(probed, [false, true])
    }

    // MARK: - "Could not tell" must never skip

    func testAmbiguousSelectorOnTheFastTreeIsNotAbsent() {
        let ambiguous = ElementResolutionError.multipleMatches(
            count: 3, kind: "label", value: "Delete", hasUniqueIDs: true
        )
        XCTAssertFalse(ambiguous.isNotFound, "precondition: a multiple-match is not a not-found")
        XCTAssertFalse(
            OptionalStepSkip.targetIsDefinitelyAbsent { _ in throw ambiguous },
            "an ambiguous selector is a defect to surface, not an absent target"
        )
    }

    func testAmbiguousSelectorOnTheDeepTreeIsNotAbsent() {
        XCTAssertFalse(
            OptionalStepSkip.targetIsDefinitelyAbsent { deep in
                if deep {
                    throw ElementResolutionError.multipleMatches(
                        count: 2, kind: "label", value: "Delete", hasUniqueIDs: false
                    )
                }
                return false
            },
            "an ambiguity that only the deep tree exposes must not skip either"
        )
    }

    func testUnreadableTreeIsNotAbsent() {
        XCTAssertFalse(
            OptionalStepSkip.targetIsDefinitelyAbsent { _ in throw TreeUnreadable() },
            "a tree that could not be read says nothing about the target"
        )
    }

    func testInvalidFrameIsNotAbsent() {
        let invalid = ElementResolutionError.invalidFrame(reason: "Matched element has no frame.")
        XCTAssertFalse(invalid.isNotFound, "precondition: an invalid frame is not a not-found")
        XCTAssertFalse(OptionalStepSkip.targetIsDefinitelyAbsent { _ in throw invalid })
    }

    // MARK: - Which actions can skip at all

    func testOnlyPreResolvedActionsCanSkip() {
        XCTAssertEqual(
            OptionalStepSkip.skippableActionTypes,
            ["tap", "double-tap", "long-press", "slider"]
        )
        for type in ["type", "swipe", "gesture", "privacy", "launch"] {
            XCTAssertFalse(
                OptionalStepSkip.skippableActionTypes.contains(type),
                "\(type) has no selector to come up empty, so `optional` must not skip it"
            )
        }
        XCTAssertFalse(
            OptionalStepSkip.skippableActionTypes.contains("set-text"),
            "set-text IS selector-targeted, but is deliberately excluded: a missing "
            + "field must fail the write, not turn into a green skip"
        )
    }
}
