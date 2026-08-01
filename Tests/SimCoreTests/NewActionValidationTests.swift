// NewActionValidationTests.swift
//
// Validation coverage for the action types and verify forms added to close the
// gap with Xcode 27's native device-interaction surface: double-tap, pinch,
// multitouch, display-state, voiceover, biometrics, and the structured
// `verify.elements` / regex conditions.
//
// The point of validating these up front is that `sipi validate` must never
// green-light a spec the harness will reject at run time.

import XCTest
@testable import SimCore

final class NewActionValidationTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sipi-new-action-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func validate(id: String, steps: [Any]) throws -> ResultValidator.ValidationOutcome {
        let dir = tempDir.appendingPathComponent("spec-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(id).json")
        try Data(JSONSerialization.data(withJSONObject: ["id": id, "title": "T", "steps": steps])).write(to: file)
        return ResultValidator.validateTestFile(file.path)
    }

    private func action(_ action: [String: Any]) -> [Any] {
        [["action": action]]
    }

    // MARK: - double-tap

    func testDoubleTapValidates() throws {
        let outcome = try validate(id: "dt-ok", steps: action(["type": "double-tap", "selector": ["label": "Map"]]))
        XCTAssertTrue(outcome.isValid, "\(outcome.errors)")
    }

    func testDoubleTapRejectsBothSelectorAndPoint() throws {
        let outcome = try validate(id: "dt-both", steps: action([
            "type": "double-tap", "selector": ["label": "Map"], "point": ["x": 0.5, "y": 0.5]
        ]))
        XCTAssertFalse(outcome.isValid)
    }

    // MARK: - pinch

    func testPinchValidates() throws {
        let outcome = try validate(id: "pinch-ok", steps: action([
            "type": "pinch", "direction": "out", "separation": 0.5, "duration": 0.4, "steps": 20
        ]))
        XCTAssertTrue(outcome.isValid, "\(outcome.errors)")
    }

    func testPinchRequiresDirection() throws {
        let outcome = try validate(id: "pinch-nodir", steps: action(["type": "pinch"]))
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("requires a direction") }, "\(outcome.errors)")
    }

    func testPinchRejectsUnknownDirection() throws {
        let outcome = try validate(id: "pinch-bad", steps: action(["type": "pinch", "direction": "sideways"]))
        XCTAssertFalse(outcome.isValid)
    }

    func testPinchRejectsSeparationAtMinimum() throws {
        let outcome = try validate(id: "pinch-sep", steps: action([
            "type": "pinch", "direction": "in", "separation": 0.05
        ]))
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("separation") }, "\(outcome.errors)")
    }

    /// The saved-test bound must match `sipi pinch`: zero collapses the gesture
    /// into a single instant frame that no recognizer reads as a pinch, and the
    /// shared 0...600 seconds range would let both through.
    func testPinchRejectsOutOfRangeDuration() throws {
        for duration in [0, 31, 600] {
            let outcome = try validate(id: "pinch-dur-\(duration)", steps: action([
                "type": "pinch", "direction": "out", "duration": duration
            ]))
            XCTAssertFalse(outcome.isValid, "duration \(duration) should be rejected")
            XCTAssertTrue(
                outcome.errors.contains { $0.contains("at most 30 seconds for a pinch") },
                "duration \(duration): \(outcome.errors)")
        }
    }

    func testPinchAcceptsInRangeDuration() throws {
        let outcome = try validate(id: "pinch-dur-ok", steps: action([
            "type": "pinch", "direction": "out", "duration": 0.5
        ]))
        XCTAssertTrue(outcome.isValid, "\(outcome.errors)")
    }

    /// The optional-key set is shared across action types, so a structural key
    /// with the wrong shape must be caught wherever it appears — not only on the
    /// action that reads it. Otherwise it validates and then fails to decode.
    func testStructuralKeysAreTypeCheckedOnEveryAction() throws {
        let cases: [(String, [String: Any])] = [
            ("points on tap", ["type": "tap", "selector": ["label": "X"], "points": "typo"]),
            ("settings on tap", ["type": "tap", "selector": ["label": "X"], "settings": "typo"]),
            ("points on type", ["type": "type", "text": "x", "points": 42])
        ]
        for (name, spec) in cases {
            let outcome = try validate(id: "struct-\(name.replacingOccurrences(of: " ", with: "-"))",
                                       steps: action(spec))
            XCTAssertFalse(outcome.isValid, name)
        }
    }

    /// A well-shaped outer container full of ill-typed members decodes no better
    /// than a mistyped container, so the check has to reach inside — on every
    /// action, not just the ones that read the key.
    func testStructuralKeyCONTENTSAreTypeCheckedOnEveryAction() throws {
        let cases: [(String, [String: Any], String)] = [
            ("point element is not an object",
             ["type": "tap", "selector": ["label": "X"], "points": ["typo"]],
             "points[0]"),
            ("point coordinate is not a number",
             ["type": "tap", "selector": ["label": "X"], "points": [["x": "bad", "y": 0.5]]],
             "points[0] requires numeric x and y"),
            ("facet is not a bool",
             ["type": "tap", "selector": ["label": "X"], "settings": ["reduce-motion": "yes"]],
             "settings.reduce-motion"),
            ("facet is not a number",
             ["type": "type", "text": "x", "settings": ["liquid-glass-opacity": "1.0"]],
             "settings.liquid-glass-opacity"),
            ("facet is not a string",
             ["type": "tap", "selector": ["label": "X"], "settings": ["color-filter-type": 3]],
             "settings.color-filter-type")
        ]
        for (name, spec, expectedPath) in cases {
            let outcome = try validate(id: "nested-\(abs(name.hashValue))", steps: action(spec))
            XCTAssertFalse(outcome.isValid, name)
            XCTAssertTrue(
                outcome.errors.contains { $0.contains(expectedPath) },
                "\(name): expected an error naming \(expectedPath), got \(outcome.errors)")
        }
    }

    // MARK: - multitouch

    func testMultitouchValidates() throws {
        let outcome = try validate(id: "mt-ok", steps: action([
            "type": "multitouch", "phase": 1,
            "points": [["x": 0.4, "y": 0.4], ["x": 0.6, "y": 0.6]]
        ]))
        XCTAssertTrue(outcome.isValid, "\(outcome.errors)")
    }

    func testMultitouchRequiresExactlyTwoPoints() throws {
        let outcome = try validate(id: "mt-one", steps: action([
            "type": "multitouch", "phase": 1, "points": [["x": 0.4, "y": 0.4]]
        ]))
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("exactly two points") }, "\(outcome.errors)")
    }

    func testMultitouchRejectsUnknownPhase() throws {
        let outcome = try validate(id: "mt-phase", steps: action([
            "type": "multitouch", "phase": 3,
            "points": [["x": 0.4, "y": 0.4], ["x": 0.6, "y": 0.6]]
        ]))
        XCTAssertFalse(outcome.isValid)
    }

    // MARK: - display-state

    func testDisplayStateValidates() throws {
        let outcome = try validate(id: "ds-ok", steps: action([
            "type": "display-state",
            "settings": [
                "reduce-motion": true,
                "reduce-transparency": false,
                "color-filter": true,
                "color-filter-type": "deuteranopia",
                "color-filter-intensity": 0.8,
                "liquid-glass-opacity": 1.0
            ]
        ]))
        XCTAssertTrue(outcome.isValid, "\(outcome.errors)")
    }

    /// A misspelled facet must be an error: devicectl would ignore it silently and
    /// the test would pass while the state was never applied.
    func testDisplayStateRejectsUnknownFacet() throws {
        let outcome = try validate(id: "ds-typo", steps: action([
            "type": "display-state", "settings": ["reduce_motion": true]
        ]))
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("unknown facets") }, "\(outcome.errors)")
    }

    func testDisplayStateRejectsEmptySettings() throws {
        let outcome = try validate(id: "ds-empty", steps: action([
            "type": "display-state", "settings": [String: Any]()
        ]))
        XCTAssertFalse(outcome.isValid)
    }

    func testDisplayStateRejectsOutOfRangeIntensity() throws {
        let outcome = try validate(id: "ds-range", steps: action([
            "type": "display-state", "settings": ["color-filter-intensity": 0.1]
        ]))
        XCTAssertFalse(outcome.isValid)
    }

    /// The range guards read through `numberValue`, which yields nil for a string
    /// or a bool — without an explicit type check those would validate and then
    /// fail at decode time, which is exactly the gap `sipi validate` exists to
    /// close.
    func testDisplayStateRejectsNonNumericNumericFacets() throws {
        let badValues: [Any] = ["0.5", true]
        for facet in ["liquid-glass-opacity", "color-filter-intensity"] {
            for value in badValues {
                let outcome = try validate(id: "ds-\(facet)-\(value)", steps: action([
                    "type": "display-state", "settings": ["color-filter": true, facet: value]
                ]))
                XCTAssertFalse(outcome.isValid, "\(facet) = \(value) should be rejected")
                XCTAssertTrue(
                    outcome.errors.contains { $0.contains("\(facet) must be number") },
                    "\(facet) = \(value): \(outcome.errors)")
            }
        }
    }

    func testDisplayStateRejectsWrongFacetType() throws {
        let outcome = try validate(id: "ds-type", steps: action([
            "type": "display-state", "settings": ["reduce-motion": "yes"]
        ]))
        XCTAssertFalse(outcome.isValid)
    }

    /// devicectl refuses an intensity alongside the grayscale filter, and a
    /// refused write leaves the whole batch unapplied — so this has to fail
    /// validation rather than the run.
    func testDisplayStateRejectsGrayscaleWithIntensity() throws {
        let outcome = try validate(id: "ds-gray", steps: action([
            "type": "display-state",
            "settings": ["color-filter": true, "color-filter-type": "grayscale", "color-filter-intensity": 0.5]
        ]))
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("does not take one") }, "\(outcome.errors)")
    }

    func testDisplayStateAllowsGrayscaleWithoutIntensity() throws {
        let outcome = try validate(id: "ds-gray-ok", steps: action([
            "type": "display-state", "settings": ["color-filter": true, "color-filter-type": "grayscale"]
        ]))
        XCTAssertTrue(outcome.isValid, "\(outcome.errors)")
    }

    func testDisplayStateAllowsIntensityWithNonGrayscaleFilter() throws {
        let outcome = try validate(id: "ds-deut", steps: action([
            "type": "display-state",
            "settings": ["color-filter": true, "color-filter-type": "deuteranopia", "color-filter-intensity": 0.5]
        ]))
        XCTAssertTrue(outcome.isValid, "\(outcome.errors)")
    }

    /// devicectl only reports the filter's kind and intensity while the filter is
    /// ON, so a run starting with it off has no baseline for them. Requiring
    /// `color-filter` alongside keeps the restore honest.
    func testDisplayStateRejectsFilterDetailWithoutTheFilterItself() throws {
        for detail in ["color-filter-type": "deuteranopia", "color-filter-intensity": 0.5] as [String: Any] {
            let outcome = try validate(id: "ds-orphan-\(detail.key)", steps: action([
                "type": "display-state", "settings": [detail.key: detail.value]
            ]))
            XCTAssertFalse(outcome.isValid, "\(detail.key) alone should be rejected")
            XCTAssertTrue(
                outcome.errors.contains { $0.contains("without color-filter") },
                "\(detail.key): \(outcome.errors)")
        }
    }

    // MARK: - voiceover / biometrics

    func testVoiceOverValidates() throws {
        XCTAssertTrue(try validate(id: "vo-ok", steps: action(["type": "voiceover", "enabled": true])).isValid)
    }

    func testVoiceOverRequiresEnabled() throws {
        XCTAssertFalse(try validate(id: "vo-none", steps: action(["type": "voiceover"])).isValid)
    }

    func testBiometricsOperationsValidate() throws {
        for operation in ["enroll", "unenroll", "match", "no-match"] {
            let outcome = try validate(id: "bio-\(operation)", steps: action([
                "type": "biometrics", "operation": operation
            ]))
            XCTAssertTrue(outcome.isValid, "\(operation): \(outcome.errors)")
        }
    }

    func testBiometricsRejectsUnknownOperation() throws {
        XCTAssertFalse(try validate(id: "bio-bad", steps: action([
            "type": "biometrics", "operation": "scan"
        ])).isValid)
    }

    // MARK: - verify: regex

    func testRegexVerifyValidates() throws {
        let outcome = try validate(id: "rx-ok", steps: [[
            "verify": ["matches": ["Total: \\d+"], "not-matches": ["Error \\d+"]]
        ]])
        XCTAssertTrue(outcome.isValid, "\(outcome.errors)")
    }

    func testUncompilablePatternIsRejected() throws {
        let outcome = try validate(id: "rx-bad", steps: [["verify": ["matches": ["[unclosed"]]]])
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("valid regular expression") }, "\(outcome.errors)")
    }

    func testEmptyPatternIsRejected() throws {
        XCTAssertFalse(try validate(id: "rx-empty", steps: [["verify": ["matches": ["  "]]]]).isValid)
    }

    // MARK: - verify: elements

    func testElementConditionValidates() throws {
        let outcome = try validate(id: "el-ok", steps: [[
            "verify": ["elements": [
                ["label": "Sign In", "enabled": true],
                ["element-type": "Cell", "count": 5],
                ["id": "auth.email", "value-matches": "@example\\.com$"],
                ["label": "Close", "min-width": 44, "min-height": 44]
            ]]
        ]])
        XCTAssertTrue(outcome.isValid, "\(outcome.errors)")
    }

    /// A condition with no selector would apply to the whole screen, which is
    /// never what the author meant.
    func testElementConditionRequiresSelector() throws {
        let outcome = try validate(id: "el-nosel", steps: [["verify": ["elements": [["enabled": true]]]]])
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("requires at least one selector") }, "\(outcome.errors)")
    }

    func testElementConditionRejectsUnknownKey() throws {
        let outcome = try validate(id: "el-typo", steps: [[
            "verify": ["elements": [["label": "X", "min_width": 44]]]
        ]])
        XCTAssertFalse(outcome.isValid)
    }

    func testElementConditionRejectsContradictoryCounts() throws {
        let outcome = try validate(id: "el-counts", steps: [[
            "verify": ["elements": [["element-type": "Cell", "min-count": 5, "max-count": 2]]]
        ]])
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("greater than max-count") }, "\(outcome.errors)")
    }

    func testElementConditionRejectsCountWithMinCount() throws {
        let outcome = try validate(id: "el-mix", steps: [[
            "verify": ["elements": [["element-type": "Cell", "count": 3, "min-count": 1]]]
        ]])
        XCTAssertFalse(outcome.isValid)
    }

    /// An absent element has no properties, so asserting one alongside
    /// `exists: false` can never hold.
    func testElementConditionRejectsAbsenceWithProperty() throws {
        let outcome = try validate(id: "el-absurd", steps: [[
            "verify": ["elements": [["label": "Gone", "exists": false, "enabled": true]]]
        ]])
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("no properties to check") }, "\(outcome.errors)")
    }

    func testElementConditionRejectsNegativeCount() throws {
        XCTAssertFalse(try validate(id: "el-neg", steps: [[
            "verify": ["elements": [["element-type": "Cell", "count": -1]]]
        ]]).isValid)
    }

    func testElementConditionRejectsBadValueMatchesPattern() throws {
        XCTAssertFalse(try validate(id: "el-rx", steps: [[
            "verify": ["elements": [["id": "x", "value-matches": "[bad"]]]
        ]]).isValid)
    }

    /// An `elements`-only verify is a real verify, not a vacuous one.
    func testElementsOnlyVerifySatisfiesTheNonVacuousRule() throws {
        let outcome = try validate(id: "el-only", steps: [[
            "verify": ["elements": [["label": "Sign In"]]]
        ]])
        XCTAssertTrue(outcome.isValid, "\(outcome.errors)")
    }

    // MARK: - type verify-effect

    func testTypeAcceptsVerifyEffect() throws {
        let outcome = try validate(id: "type-ve", steps: action([
            "type": "type", "text": "hello", "verify-effect": false
        ]))
        XCTAssertTrue(outcome.isValid, "\(outcome.errors)")
    }

    func testVerifyEffectMustBeBoolean() throws {
        XCTAssertFalse(try validate(id: "type-ve-bad", steps: action([
            "type": "type", "text": "hello", "verify-effect": "no"
        ])).isValid)
    }
}
