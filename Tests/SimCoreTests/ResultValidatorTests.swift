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
            "steps": [["action": "tap Login"]]
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
            "steps": [["action": "tap Login"]]
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
            try write(["id": "f", "title": "T", "steps": [["action": "tap"]]],
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
        try write(["id": "f", "title": "T", "steps": [["action": "tap"]]],
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
}
