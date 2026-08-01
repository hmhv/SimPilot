// ResultValidatorTests.swift
//
// Locks the `.simpilot` workspace validation that moved INTO the sipi binary
// (STAGE REPORT): formerly the loose interpreter script
// validate_simpilot_results.swift, now SimCore.ResultValidator behind
// `sipi validate`. These build small fixture workspaces on disk and assert the
// expected pass / fail / cross-file-consistency behavior.

import XCTest
import Foundation
@testable import SimCore

final class ResultValidatorTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sipi-validate-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    private func write(_ object: Any, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(JSONSerialization.data(withJSONObject: object)).write(to: url)
    }

    func testMinimalValidWorkspacePasses() throws {
        let ws = tempDir.appendingPathComponent(".simpilot", isDirectory: true)
        try write(["app": "com.example.App"], to: ws.appendingPathComponent("config.json"))

        let outcome = try ResultValidator.validate(workspace: ws.path)
        XCTAssertTrue(outcome.isValid, "minimal config-only workspace should validate: \(outcome.errors)")
        XCTAssertTrue(outcome.errors.isEmpty)
    }

    func testMissingConfigReportsError() throws {
        let ws = tempDir.appendingPathComponent("ws-no-config", isDirectory: true)
        try FileManager.default.createDirectory(at: ws, withIntermediateDirectories: true)

        let outcome = try ResultValidator.validate(workspace: ws.path)
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("config.json") && $0.contains("missing file") },
                      "expected a missing config.json error, got \(outcome.errors)")
    }

    func testNonexistentWorkspaceThrows() {
        let missing = tempDir.appendingPathComponent("does-not-exist").path
        XCTAssertThrowsError(try ResultValidator.validate(workspace: missing)) { error in
            XCTAssertTrue(error is ResultValidator.ValidationError,
                          "a missing workspace should throw ValidationError")
        }
    }

    func testRunResultPassedMismatchIsAnError() throws {
        let ws = tempDir.appendingPathComponent(".simpilot", isDirectory: true)
        try write(["app": "com.example.App"], to: ws.appendingPathComponent("config.json"))

        // A test definition with one step.
        try write([
            "id": "login-flow",
            "title": "Login",
            "steps": [["action": ["type": "tap", "selector": ["label": "Login"]]]]
        ], to: ws.appendingPathComponent("tests/login-flow.json"))

        // run.json claims passed=true...
        let runDir = ws.appendingPathComponent("runs/2026-06-19_100000", isDirectory: true)
        try write([
            "started": "2026-06-19T10:00:00+09:00",
            "device": "udid",
            "tests": [["id": "login-flow", "passed": true, "duration": 1.0]],
            "summary": ["total": 1, "passed": 1, "failed": 0]
        ], to: runDir.appendingPathComponent("run.json"))

        // ...but result.json says passed=false.
        try write([
            "id": "login-flow",
            "passed": false,
            "duration": 1.0,
            "steps": [["passed": false, "action": "tap Login"]]
        ], to: runDir.appendingPathComponent("login-flow/result.json"))

        let outcome = try ResultValidator.validate(workspace: ws.path)
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("passed=true") && $0.contains("passed=false") },
                      "expected a run/result passed mismatch error, got \(outcome.errors)")
    }

    // MARK: - Timestamp (ISO 8601 with timezone offset) validation
    //
    // AGENTS.md: "Run/result timestamps must be ISO 8601 with timezone offset."
    // These exercise ResultValidator's timestamp check in isolation by varying
    // only run.json's `started` value and asserting on the timestamp-specific
    // diagnostic (so they are unaffected by the workspace's other rules).

    /// Build a workspace whose run.json carries the given `started` value.
    private func makeRunWorkspace(started: Any) throws -> URL {
        let ws = tempDir.appendingPathComponent(".simpilot", isDirectory: true)
        try write(["app": "com.example.App"], to: ws.appendingPathComponent("config.json"))
        try write([
            "id": "login-flow",
            "title": "Login",
            "steps": [["action": ["type": "tap", "selector": ["label": "Login"]]]]
        ], to: ws.appendingPathComponent("tests/login-flow.json"))
        let runDir = ws.appendingPathComponent("runs/2026-06-19_100000", isDirectory: true)
        try write([
            "started": started,
            "device": "udid",
            "tests": [["id": "login-flow", "passed": true, "duration": 1.0]],
            "summary": ["total": 1, "passed": 1, "failed": 0]
        ], to: runDir.appendingPathComponent("run.json"))
        try write([
            "id": "login-flow",
            "passed": true,
            "duration": 1.0,
            "steps": [["passed": true, "action": "tap Login"]]
        ], to: runDir.appendingPathComponent("login-flow/result.json"))
        return ws
    }

    private func hasTimestampError(_ errors: [String]) -> Bool {
        errors.contains { $0.contains("started") && $0.contains("ISO 8601") }
    }

    func testValidISO8601TimestampHasNoTimestampError() throws {
        for value in [
            "2026-06-19T10:00:00+09:00",     // offset
            "2026-06-19T01:00:00Z",          // UTC "Z"
            "2026-06-19T10:00:00.500+09:00"  // fractional seconds
        ] {
            let ws = try makeRunWorkspace(started: value)
            let outcome = try ResultValidator.validate(workspace: ws.path)
            XCTAssertFalse(hasTimestampError(outcome.errors),
                           "valid ISO 8601 '\(value)' must not raise a timestamp error, got \(outcome.errors)")
            XCTAssertTrue(outcome.isValid,
                          "the fixture with valid timestamp '\(value)' should fully validate, got \(outcome.errors)")
        }
    }

    func testMalformedTimestampStringIsAnError() throws {
        let ws = try makeRunWorkspace(started: "not-a-date+09:00")
        let outcome = try ResultValidator.validate(workspace: ws.path)
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(hasTimestampError(outcome.errors),
                      "a malformed timestamp string must be a timestamp error, got \(outcome.errors)")
    }

    func testNumericTimestampIsAnError() throws {
        let ws = try makeRunWorkspace(started: 1_234_567_890)
        let outcome = try ResultValidator.validate(workspace: ws.path)
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(hasTimestampError(outcome.errors),
                      "a numeric (non-string) timestamp must be a timestamp error, got \(outcome.errors)")
    }

    func testTimestampMissingSecondsIsAnError() throws {
        let ws = try makeRunWorkspace(started: "2026-06-19T10:00+09:00")
        let outcome = try ResultValidator.validate(workspace: ws.path)
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(hasTimestampError(outcome.errors),
                      "an ISO 8601 timestamp without seconds must be a timestamp error, got \(outcome.errors)")
    }

    // MARK: - Number vs. boolean type checks (NSNumber / Bool bridging)
    //
    // JSONSerialization parses JSON `true`/`false` to a CFBoolean and numbers to
    // NSNumber, but Swift's `is Bool` also matches the NSNumbers 0 and 1. The
    // validator distinguishes them via CFBooleanGetTypeID; these lock that: a
    // whole-number duration (0/1) must be accepted as a number, and a numeric
    // `passed` must be rejected as a non-bool.

    func testWholeNumberDurationIsAcceptedAsNumber() throws {
        // 0 and 1 round-trip through JSONSerialization as the NSNumbers most prone
        // to the `is Bool` bridging gotcha.
        for d in [0, 1] {
            let ws = tempDir.appendingPathComponent(".simpilot-dur-\(d)", isDirectory: true)
            try write(["app": "com.example.App"], to: ws.appendingPathComponent("config.json"))
            try write(["id": "f", "title": "T", "steps": [["action": ["type": "tap", "selector": ["label": "Tap"]]]]],
                      to: ws.appendingPathComponent("tests/f.json"))
            let runDir = ws.appendingPathComponent("runs/2026-06-19_100000", isDirectory: true)
            try write([
                "started": "2026-06-19T10:00:00+09:00",
                "device": "udid",
                "tests": [["id": "f", "passed": true, "duration": d]],
                "summary": ["total": 1, "passed": 1, "failed": 0]
            ], to: runDir.appendingPathComponent("run.json"))
            try write([
                "id": "f", "passed": true, "duration": d,
                "steps": [["passed": true, "action": "tap"]]
            ], to: runDir.appendingPathComponent("f/result.json"))

            let outcome = try ResultValidator.validate(workspace: ws.path)
            XCTAssertFalse(outcome.errors.contains { $0.contains("duration") && $0.contains("must be number") },
                           "whole-number duration \(d) must be accepted as a number, got \(outcome.errors)")
        }
    }

    func testNumericPassedIsRejectedAsNonBool() throws {
        let ws = tempDir.appendingPathComponent(".simpilot-numbool", isDirectory: true)
        try write(["app": "com.example.App"], to: ws.appendingPathComponent("config.json"))
        try write(["id": "f", "title": "T", "steps": [["action": ["type": "tap", "selector": ["label": "Tap"]]]]],
                  to: ws.appendingPathComponent("tests/f.json"))
        let runDir = ws.appendingPathComponent("runs/2026-06-19_100000", isDirectory: true)
        // `passed` is the number 1, not a JSON boolean — it must be rejected.
        try write([
            "started": "2026-06-19T10:00:00+09:00",
            "device": "udid",
            "tests": [["id": "f", "passed": 1, "duration": 1.5]],
            "summary": ["total": 1, "passed": 1, "failed": 0]
        ], to: runDir.appendingPathComponent("run.json"))
        try write([
            "id": "f", "passed": true, "duration": 1.5,
            "steps": [["passed": true, "action": "tap"]]
        ], to: runDir.appendingPathComponent("f/result.json"))

        let outcome = try ResultValidator.validate(workspace: ws.path)
        XCTAssertTrue(outcome.errors.contains { $0.contains("passed") && $0.contains("must be bool") },
                      "a numeric `passed` must be rejected as a non-bool, got \(outcome.errors)")
    }

    // MARK: - Extended v2 action types (slider / gesture / long-press / key-combo /
    // key-sequence / drag / orientation / crown). These let the deterministic
    // harness drive the richer sipi primitives as saved test steps; the validator
    // must accept the new `action.type` values and their fields.

    func testExtendedActionTypesAndFieldsValidate() throws {
        let ws = tempDir.appendingPathComponent(".simpilot-ext", isDirectory: true)
        try write(["app": "com.example.App"], to: ws.appendingPathComponent("config.json"))
        try write([
            "id": "extended-actions",
            "title": "Extended actions",
            "steps": [
                ["action": ["type": "long-press", "selector": ["label": "Photo"], "duration": 0.6]],
                ["action": ["type": "slider", "selector": ["label": "Volume", "element-type": "Slider"], "value": 75, "tolerance": 0.02]],
                ["action": ["type": "gesture", "preset": "scroll-down"]],
                ["action": ["type": "drag", "start": ["x": 0.5, "y": 0.7], "end": ["x": 0.5, "y": 0.3], "steps": 60, "duration": 0.6]],
                ["action": ["type": "key-combo", "modifiers": [227], "key": 4]],
                ["action": ["type": "key-sequence", "keycodes": [11, 8, 15], "delay": 0.1]],
                ["action": ["type": "orientation", "orientation": "landscape-left"]],
                ["action": ["type": "crown", "delta": 40]]
            ]
        ], to: ws.appendingPathComponent("tests/extended-actions.json"))

        let outcome = try ResultValidator.validate(workspace: ws.path)
        XCTAssertTrue(outcome.isValid, "extended action types/fields should validate: \(outcome.errors)")
        XCTAssertTrue(outcome.errors.isEmpty, "no errors expected, got \(outcome.errors)")
    }

    func testNewActionFieldsAreNotUnknownKeys() throws {
        // Every new scalar/array field must be recognized, not flagged "unknown keys".
        let ws = tempDir.appendingPathComponent(".simpilot-fields", isDirectory: true)
        try write(["app": "com.example.App"], to: ws.appendingPathComponent("config.json"))
        try write([
            "id": "field-coverage",
            "title": "Field coverage",
            "steps": [["action": [
                "type": "slider", "selector": ["id": "vol"], "value": 50, "tolerance": 0.05,
                "preset": "scroll-down", "modifiers": [227], "key": 4,
                "keycodes": [11], "delay": 0.1, "steps": 60, "orientation": "portrait", "delta": 10
            ]]]
        ], to: ws.appendingPathComponent("tests/field-coverage.json"))

        let outcome = try ResultValidator.validate(workspace: ws.path)
        XCTAssertFalse(outcome.errors.contains { $0.contains("unknown keys") },
                       "new action fields must be recognized, got \(outcome.errors)")
    }

    func testUnknownActionTypeIsRejected() throws {
        let ws = tempDir.appendingPathComponent(".simpilot-badtype", isDirectory: true)
        try write(["app": "com.example.App"], to: ws.appendingPathComponent("config.json"))
        try write([
            "id": "bad-action",
            "title": "Bad action",
            "steps": [["action": ["type": "frobnicate", "selector": ["label": "X"]]]]
        ], to: ws.appendingPathComponent("tests/bad-action.json"))

        let outcome = try ResultValidator.validate(workspace: ws.path)
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("action.type must be one of") },
                      "an unknown action type must be rejected, got \(outcome.errors)")
    }

    // MARK: - Strengthened per-action validation (release hardening)
    //
    // `sipi validate` (and `run-test`, which now calls validateTestFile before
    // running) must reject specs that would only fail at runtime: missing required
    // fields, ambiguous selectors, and out-of-range values.

    private func validateSpec(id: String, steps: [Any]) throws -> ResultValidator.ValidationOutcome {
        let dir = tempDir.appendingPathComponent("spec-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(id).json")
        try Data(JSONSerialization.data(withJSONObject: ["id": id, "title": "T", "steps": steps])).write(to: file)
        return ResultValidator.validateTestFile(file.path)
    }

    func testValidTapSpecValidates() throws {
        let outcome = try validateSpec(id: "tap-ok", steps: [["action": ["type": "tap", "selector": ["label": "Login"]]]])
        XCTAssertTrue(outcome.isValid, "\(outcome.errors)")
    }

    func testValidExtendedSpecValidatesViaFile() throws {
        let outcome = try validateSpec(id: "ext", steps: [
            ["action": ["type": "swipe", "start": ["x": 0.5, "y": 0.8], "end": ["x": 0.5, "y": 0.2]]],
            ["action": ["type": "key-combo", "modifiers": [227], "key": 4]],
            ["action": ["type": "crown", "delta": 20]],
            ["action": ["type": "orientation", "orientation": "landscape-left"]]
        ])
        XCTAssertTrue(outcome.isValid, "\(outcome.errors)")
    }

    func testTapWithoutSelectorOrPointIsRejected() throws {
        let outcome = try validateSpec(id: "tap-bad", steps: [["action": ["type": "tap"]]])
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("exactly one of selector or point") }, "\(outcome.errors)")
    }

    func testTapWithBothSelectorAndPointIsRejected() throws {
        let outcome = try validateSpec(id: "tap-both", steps: [["action": ["type": "tap", "selector": ["id": "x"], "point": ["x": 0.5, "y": 0.5]]]])
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("exactly one of selector or point") }, "\(outcome.errors)")
    }

    func testSelectorWithTwoIdentifiersIsRejected() throws {
        let outcome = try validateSpec(id: "sel-two", steps: [["action": ["type": "tap", "selector": ["id": "x", "label": "y"]]]])
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("exactly one of id, label, or value") }, "\(outcome.errors)")
    }

    func testSliderWithoutValueIsRejected() throws {
        let outcome = try validateSpec(id: "slider-noval", steps: [["action": ["type": "slider", "selector": ["label": "Vol"]]]])
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("slider") && $0.contains("value") }, "\(outcome.errors)")
    }

    func testSliderValueOutOfRangeIsRejected() throws {
        let outcome = try validateSpec(id: "slider-hi", steps: [["action": ["type": "slider", "selector": ["label": "Vol"], "value": 150]]])
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("between 0 and 100") }, "\(outcome.errors)")
    }

    func testKeycodeOutOfRangeIsRejected() throws {
        let outcome = try validateSpec(id: "key-hi", steps: [["action": ["type": "key", "usage": 999]]])
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("keycode") }, "\(outcome.errors)")
    }

    func testKeySequenceEmptyIsRejected() throws {
        let outcome = try validateSpec(id: "seq-empty", steps: [["action": ["type": "key-sequence", "keycodes": []]]])
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("keycodes") }, "\(outcome.errors)")
    }

    func testInvalidButtonIsRejected() throws {
        let outcome = try validateSpec(id: "btn-bad", steps: [["action": ["type": "button", "button": "power"]]])
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("button must be one of") }, "\(outcome.errors)")
    }

    func testInvalidGesturePresetIsRejected() throws {
        let outcome = try validateSpec(id: "gest-bad", steps: [["action": ["type": "gesture", "preset": "twirl"]]])
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("preset must be one of") }, "\(outcome.errors)")
    }

    func testInvalidOrientationIsRejected() throws {
        let outcome = try validateSpec(id: "ori-bad", steps: [["action": ["type": "orientation", "orientation": "sideways"]]])
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("orientation must be one of") }, "\(outcome.errors)")
    }

    func testTypeWithoutTextIsRejected() throws {
        let outcome = try validateSpec(id: "type-notext", steps: [["action": ["type": "type"]]])
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("text string") }, "\(outcome.errors)")
    }

    func testStepWaitWrongTypeIsRejected() throws {
        let outcome = try validateSpec(id: "wait-str", steps: [["action": ["type": "wait"], "wait": "soon"]])
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("wait") && $0.contains("must be number") }, "\(outcome.errors)")
    }

    func testStepOptionalWrongTypeIsRejected() throws {
        let outcome = try validateSpec(id: "opt-str", steps: [["action": ["type": "tap", "selector": ["id": "x"]], "optional": "yes"]])
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("optional") && $0.contains("must be bool") }, "\(outcome.errors)")
    }

    func testPointMissingCoordinateIsRejected() throws {
        let outcome = try validateSpec(id: "pt-bad", steps: [["action": ["type": "tap", "point": ["x": 0.5]]]])
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("numeric x and y") }, "\(outcome.errors)")
    }

    // MARK: - Type checks that keep "validate" in step with what "run" can decode

    func testNonStringActionTypeIsRejected() throws {
        let outcome = try validateSpec(id: "type-num", steps: [["action": ["type": 123]]])
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("type must be a string") }, "\(outcome.errors)")
    }

    func testNonStringSelectorIdIsRejected() throws {
        let outcome = try validateSpec(id: "sel-num", steps: [["action": ["type": "tap", "selector": ["id": 123]]]])
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("selector.id must be a string") }, "\(outcome.errors)")
    }

    func testWrongTypeDurationIsRejected() throws {
        let outcome = try validateSpec(id: "dur-str", steps: [["action": ["type": "tap", "selector": ["id": "x"], "duration": "slow"]]])
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("duration must be number") }, "\(outcome.errors)")
    }

    func testNonStringTitleIsRejected() throws {
        let dir = tempDir.appendingPathComponent("spec-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("title-num.json")
        try Data(JSONSerialization.data(withJSONObject: [
            "id": "title-num", "title": 7,
            "steps": [["action": ["type": "tap", "selector": ["id": "x"]]]]
        ])).write(to: file)
        let outcome = ResultValidator.validateTestFile(file.path)
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("title must be a string") }, "\(outcome.errors)")
    }

    func testEmptyVerifyObjectIsRejected() throws {
        let outcome = try validateSpec(id: "verify-empty", steps: [["verify": [String: Any]()]])
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("must have at least one contains") }, "\(outcome.errors)")
    }

    func testEmptyVerifyArraysAreRejected() throws {
        let outcome = try validateSpec(id: "verify-empties", steps: [["verify": ["contains": [String]()]]])
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("must have at least one contains") }, "\(outcome.errors)")
    }

    func testVerifyOnlyStepWithConditionValidates() throws {
        let outcome = try validateSpec(id: "verify-ok", steps: [["verify": ["contains": ["Home"]]]])
        XCTAssertTrue(outcome.isValid, "\(outcome.errors)")
    }

    func testFractionalStepsIsRejected() throws {
        let outcome = try validateSpec(id: "steps-frac", steps: [[
            "action": ["type": "drag", "start": ["x": 0.0, "y": 0.0], "end": ["x": 1.0, "y": 1.0], "steps": 1.5]
        ]])
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("steps must be an integer") }, "\(outcome.errors)")
    }

    func testNonIntegerKeycodesArrayIsRejected() throws {
        let outcome = try validateSpec(id: "keys-str", steps: [[
            "action": ["type": "tap", "selector": ["id": "x"], "keycodes": ["a"]]
        ]])
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("keycodes must be an array of integers") }, "\(outcome.errors)")
    }

    // MARK: - Empty/whitespace verify conditions and coordinate ranges

    func testEmptyStringVerifyConditionIsRejected() throws {
        let outcome = try validateSpec(id: "verify-blank", steps: [["verify": ["contains": [""]]]])
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("must not be empty or whitespace") }, "\(outcome.errors)")
    }

    func testWhitespaceVerifyConditionIsRejected() throws {
        let outcome = try validateSpec(id: "verify-ws", steps: [["verify": ["absent": ["   "]]]])
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("must not be empty or whitespace") }, "\(outcome.errors)")
    }

    func testNormPointOutOfRangeIsRejected() throws {
        let outcome = try validateSpec(id: "norm-oob", steps: [["action": ["type": "tap", "point": ["x": 2, "y": 0.5]]]])
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("within 0...1") }, "\(outcome.errors)")
    }

    func testNegativePixelPointIsRejected() throws {
        let outcome = try validateSpec(id: "px-neg", steps: [["action": ["type": "tap", "point": ["x": -5, "y": 0, "unit": "pixel"]]]])
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("non-negative") }, "\(outcome.errors)")
    }

    func testValidPixelPointValidates() throws {
        let outcome = try validateSpec(id: "px-ok", steps: [["action": ["type": "tap", "point": ["x": 200, "y": 700, "unit": "pixel"]]]])
        XCTAssertTrue(outcome.isValid, "\(outcome.errors)")
    }

    // MARK: - config / suite validate ⇒ decode, and suite id path safety

    func testNumericConfigAppIsRejected() throws {
        let ws = tempDir.appendingPathComponent(".simpilot-badapp", isDirectory: true)
        try write(["app": 123], to: ws.appendingPathComponent("config.json"))
        let outcome = try ResultValidator.validate(workspace: ws.path)
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("app must be a string") }, "\(outcome.errors)")
    }

    func testSuiteTraversalTestIdIsRejected() throws {
        let ws = tempDir.appendingPathComponent(".simpilot-suite-trav", isDirectory: true)
        try write(["app": "com.x"], to: ws.appendingPathComponent("config.json"))
        try write(["name": "reg", "tests": ["../../evil"]], to: ws.appendingPathComponent("suites/reg.json"))
        let outcome = try ResultValidator.validate(workspace: ws.path)
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("kebab-case test id") }, "\(outcome.errors)")
    }

    func testSuiteWrongTypeSettingIsRejected() throws {
        let ws = tempDir.appendingPathComponent(".simpilot-suite-settings", isDirectory: true)
        try write(["app": "com.x"], to: ws.appendingPathComponent("config.json"))
        try write(["name": "reg", "tests": ["good"], "settings": ["stop-on-failure": "yes"]],
                  to: ws.appendingPathComponent("suites/reg.json"))
        let outcome = try ResultValidator.validate(workspace: ws.path)
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("stop-on-failure") && $0.contains("must be bool") }, "\(outcome.errors)")
    }

    // MARK: - Empty steps, integer overflow, and time-field ranges

    func testEmptyStepsIsRejected() throws {
        let outcome = try validateSpec(id: "no-steps", steps: [])
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("at least one step") }, "\(outcome.errors)")
    }

    func testIntegerOverflowIsRejected() throws {
        let outcome = try validateSpec(id: "int-overflow", steps: [[
            "action": ["type": "drag", "start": ["x": 0.0, "y": 0.0], "end": ["x": 1.0, "y": 1.0], "steps": 1e20]
        ]])
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("steps must be an integer") }, "\(outcome.errors)")
    }

    func testActionDurationOutOfRangeIsRejected() throws {
        let outcome = try validateSpec(id: "dur-huge", steps: [["action": ["type": "wait", "duration": 5000]]])
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("duration must be between 0 and 600 seconds") }, "\(outcome.errors)")
    }

    func testStepWaitOutOfRangeIsRejected() throws {
        let outcome = try validateSpec(id: "wait-huge", steps: [["action": ["type": "tap", "selector": ["id": "x"]], "wait": 5000]])
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("wait must be between 0 and 600 seconds") }, "\(outcome.errors)")
    }

    // MARK: - Config practical bounds (max-retries / step-delay)

    func testConfigMaxRetriesTooLargeIsRejected() throws {
        let ws = tempDir.appendingPathComponent(".simpilot-retries", isDirectory: true)
        try write(["app": "com.x", "max-retries": 1_000_000_000], to: ws.appendingPathComponent("config.json"))
        let outcome = try ResultValidator.validate(workspace: ws.path)
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("max-retries must be between 0 and 10") }, "\(outcome.errors)")
    }

    func testConfigStepDelayTooLargeIsRejected() throws {
        let ws = tempDir.appendingPathComponent(".simpilot-delay", isDirectory: true)
        try write(["app": "com.x", "step-delay": 5000], to: ws.appendingPathComponent("config.json"))
        let outcome = try ResultValidator.validate(workspace: ws.path)
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("step-delay must be between 0 and 60 seconds") }, "\(outcome.errors)")
    }

    func testConfigWithSaneRetriesAndDelayValidates() throws {
        let ws = tempDir.appendingPathComponent(".simpilot-sane", isDirectory: true)
        try write(["app": "com.x", "max-retries": 2, "step-delay": 0.5], to: ws.appendingPathComponent("config.json"))
        let outcome = try ResultValidator.validate(workspace: ws.path)
        XCTAssertTrue(outcome.isValid, "\(outcome.errors)")
    }

    // MARK: - Config boundary values (validator ⇄ runner agreement)

    private func configOutcome(_ config: [String: Any], _ name: String) throws -> ResultValidator.ValidationOutcome {
        let ws = tempDir.appendingPathComponent(".simpilot-\(name)", isDirectory: true)
        try write(config, to: ws.appendingPathComponent("config.json"))
        return try ResultValidator.validate(workspace: ws.path)
    }

    func testConfigStepDelayZeroValidates() throws {
        // 0 is allowed by the validator and honored (no pause) by the runner.
        XCTAssertTrue(try configOutcome(["app": "com.x", "step-delay": 0], "delay0").isValid)
    }

    func testConfigStepDelayUpperBoundaryValidates() throws {
        XCTAssertTrue(try configOutcome(["app": "com.x", "step-delay": 60], "delay60").isValid)
    }

    func testConfigStepDelayJustOverBoundaryIsRejected() throws {
        let outcome = try configOutcome(["app": "com.x", "step-delay": 61], "delay61")
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("step-delay must be between 0 and 60 seconds") }, "\(outcome.errors)")
    }

    func testConfigNegativeStepDelayIsRejected() throws {
        let outcome = try configOutcome(["app": "com.x", "step-delay": -1], "delayneg")
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("step-delay must be between 0 and 60 seconds") }, "\(outcome.errors)")
    }

    func testConfigMaxRetriesBoundariesValidate() throws {
        XCTAssertTrue(try configOutcome(["app": "com.x", "max-retries": 0], "retry0").isValid)
        XCTAssertTrue(try configOutcome(["app": "com.x", "max-retries": 10], "retry10").isValid)
    }

    func testConfigMaxRetriesElevenIsRejected() throws {
        let outcome = try configOutcome(["app": "com.x", "max-retries": 11], "retry11")
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("max-retries must be between 0 and 10") }, "\(outcome.errors)")
    }

    // MARK: - Simulator test controls and network provider

    func testSimulatorControlActionsValidate() throws {
        let outcome = try validateSpec(id: "simulator-controls", steps: [
            ["action": ["type": "open-url", "url": "myapp://settings"]],
            ["action": ["type": "privacy", "operation": "reset", "service": "photos"]],
            ["action": ["type": "push", "payload": ["aps": ["alert": "Hello"]]]],
            ["action": ["type": "location", "operation": "set", "latitude": 35.6812, "longitude": 139.7671]],
            ["action": ["type": "location", "operation": "clear"]],
            ["action": ["type": "appearance", "appearance": "dark"]],
            ["action": ["type": "content-size", "content-size": "accessibility-large"]],
            ["action": ["type": "increase-contrast", "enabled": true]],
            ["action": ["type": "status-bar", "operation": "override", "arguments": ["--time", "9:41"]]],
            ["action": ["type": "status-bar", "operation": "clear"]],
            ["action": [
                "type": "launch",
                "arguments": ["--fixture"],
                "environment": ["API_MODE": "fixture"]
            ]],
            ["action": ["type": "terminate"]],
            ["action": ["type": "network-condition", "operation": "apply", "profile": "packet-loss-100"]],
            ["action": ["type": "network-condition", "operation": "clear"]]
        ])
        XCTAssertTrue(outcome.isValid, "\(outcome.errors)")
    }

    func testInvalidSimulatorControlShapesAreRejected() throws {
        let outcome = try validateSpec(id: "invalid-controls", steps: [
            ["action": ["type": "open-url", "url": "not a url"]],
            ["action": ["type": "push", "payload": ["message": "missing aps"]]],
            ["action": ["type": "location", "operation": "set", "latitude": 91, "longitude": 0]],
            ["action": ["type": "appearance", "appearance": "sepia"]],
            ["action": ["type": "network-condition", "operation": "apply", "profile": "100% Loss"]],
            ["action": ["type": "launch", "environment": ["SIMCTL_CHILD_API": "bad"]]]
        ])
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("absolute url") }, "\(outcome.errors)")
        XCTAssertTrue(outcome.errors.contains { $0.contains("aps object") }, "\(outcome.errors)")
        XCTAssertTrue(outcome.errors.contains { $0.contains("latitude") }, "\(outcome.errors)")
        XCTAssertTrue(outcome.errors.contains { $0.contains("appearance") }, "\(outcome.errors)")
        XCTAssertTrue(outcome.errors.contains { $0.contains("profile") }, "\(outcome.errors)")
        XCTAssertTrue(outcome.errors.contains { $0.contains("environment key") }, "\(outcome.errors)")
    }

    func testNetworkConditionProviderMustBeAbsolute() throws {
        let valid = try configOutcome([
            "app": "com.x",
            "network-condition-provider": "/usr/local/bin/sipi-network-provider"
        ], "provider-absolute")
        XCTAssertTrue(valid.isValid, "\(valid.errors)")

        let invalid = try configOutcome([
            "app": "com.x",
            "network-condition-provider": "./provider"
        ], "provider-relative")
        XCTAssertFalse(invalid.isValid)
        XCTAssertTrue(invalid.errors.contains { $0.contains("absolute path") }, "\(invalid.errors)")
    }

    // MARK: - type input-method

    func testTypeInputMethodValidValues() throws {
        let outcome = try validateSpec(id: "type-input-method", steps: [
            ["action": ["type": "type", "text": "こんにちは"]],
            ["action": ["type": "type", "text": "hello", "input-method": "paste"]],
            ["action": ["type": "type", "text": "1234", "input-method": "keyboard"]]
        ])
        XCTAssertTrue(outcome.isValid, "\(outcome.errors)")
    }

    func testTypeInvalidInputMethodIsRejected() throws {
        let outcome = try validateSpec(id: "type-input-method-bad", steps: [
            ["action": ["type": "type", "text": "hello", "input-method": "voice"]]
        ])
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("input-method must be paste or keyboard") }, "\(outcome.errors)")
    }

    func testTypeKeyboardMethodRejectsNonUSText() throws {
        let outcome = try validateSpec(id: "type-keyboard-non-us", steps: [
            ["action": ["type": "type", "text": "こんにちは", "input-method": "keyboard"]]
        ])
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("keyboard") && $0.contains("non-US") }, "\(outcome.errors)")
    }

    // MARK: - type clear

    func testTypeClearFlagAccepted() throws {
        let outcome = try validateSpec(id: "type-clear", steps: [
            ["action": ["type": "type", "text": "hello", "clear": true]],
            ["action": ["type": "type", "text": "hello", "clear": false, "input-method": "keyboard"]]
        ])
        XCTAssertTrue(outcome.isValid, "\(outcome.errors)")
    }

    // MARK: - set-text

    func testSetTextAcceptsSelectorOrPoint() throws {
        let outcome = try validateSpec(id: "set-text-ok", steps: [
            ["action": ["type": "set-text", "selector": ["id": "email"], "text": "a@b.c"]],
            ["action": ["type": "set-text", "point": ["x": 0.5, "y": 0.4], "text": "日本語"]]
        ])
        XCTAssertTrue(outcome.isValid, "\(outcome.errors)")
    }

    /// `verify-value: false` is the escape hatch for a field that reports masked or
    /// reformatted text (a SecureField answers with bullets), so it must validate.
    func testSetTextVerifyValueFlag() throws {
        let ok = try validateSpec(id: "set-text-unverified", steps: [
            ["action": ["type": "set-text", "selector": ["id": "password"], "text": "s3cret", "verify-value": false]]
        ])
        XCTAssertTrue(ok.isValid, "\(ok.errors)")

        let bad = try validateSpec(id: "set-text-verify-value-bad", steps: [
            ["action": ["type": "set-text", "selector": ["id": "password"], "text": "s3cret", "verify-value": "no"]]
        ])
        XCTAssertFalse(bad.isValid)
        XCTAssertTrue(bad.errors.contains { $0.contains("verify-value") }, "\(bad.errors)")
    }

    func testSetTextRequiresText() throws {
        let outcome = try validateSpec(id: "set-text-no-text", steps: [
            ["action": ["type": "set-text", "selector": ["id": "email"]]]
        ])
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("(set-text) requires a text string") }, "\(outcome.errors)")
    }

    /// Both or neither target is ambiguous the same way `tap` is, so it is rejected
    /// rather than silently preferring one.
    func testSetTextRejectsBothOrNeitherTarget() throws {
        let both = try validateSpec(id: "set-text-both", steps: [
            ["action": ["type": "set-text", "selector": ["id": "a"], "point": ["x": 0.1, "y": 0.1], "text": "x"]]
        ])
        XCTAssertFalse(both.isValid)
        XCTAssertTrue(both.errors.contains { $0.contains("(set-text) requires exactly one of selector or point") }, "\(both.errors)")

        let neither = try validateSpec(id: "set-text-neither", steps: [
            ["action": ["type": "set-text", "text": "x"]]
        ])
        XCTAssertFalse(neither.isValid)
        XCTAssertTrue(neither.errors.contains { $0.contains("(set-text) requires exactly one of selector or point") }, "\(neither.errors)")
    }

    func testTypeClearMustBeBool() throws {
        let outcome = try validateSpec(id: "type-clear-bad", steps: [
            ["action": ["type": "type", "text": "hello", "clear": "yes"]]
        ])
        XCTAssertFalse(outcome.isValid)
        XCTAssertTrue(outcome.errors.contains { $0.contains("clear") }, "\(outcome.errors)")
    }
}
