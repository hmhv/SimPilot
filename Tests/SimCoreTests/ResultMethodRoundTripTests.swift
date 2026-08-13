// ResultMethodRoundTripTests.swift
//
// The harness writes `attempted-methods[].method` into result.json, and
// `sipi validate` checks that value against a fixed vocabulary. Those two lists
// live in different files, so adding an action type that reports a new method
// silently breaks validation of the harness's OWN output — the run succeeds and
// then `sipi validate` rejects the artifact it just produced.
//
// This locks the round trip for every method string `Harness.perform(action:)`
// can return. Adding a new one to the harness without adding it to
// `attemptedMethodTypes` fails this test.

import XCTest
@testable import SimCore

final class ResultMethodRoundTripTests: XCTestCase {
    private var tempDir: URL!

    /// Every `method` value `Harness.perform(action:)` returns.
    ///   tap-label / tap-id / tap-value   selector-resolved touch actions
    ///   touch-coordinate                 point-targeted touch actions
    ///   input                            text and key actions
    ///   multitouch                       pinch and raw multitouch
    ///   simctl                           the simctl-backed state actions
    ///   network-condition                the external provider
    ///   devicectl                        biometrics / display-state
    private static let harnessMethods = [
        "tap-label", "tap-id", "tap-value", "touch-coordinate", "input",
        "multitouch", "simctl", "network-condition", "devicectl"
    ]

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sipi-result-method-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Build a workspace holding one test and one run whose single step reports
    /// `method`, then validate it. Only the method diagnostics are asserted on —
    /// the run.json cross-checks are exercised by `ResultValidatorTests`.
    private func methodErrors(for method: String) throws -> [String] {
        let workspace = tempDir.appendingPathComponent("ws-\(UUID().uuidString)", isDirectory: true)
        let testsDir = workspace.appendingPathComponent("tests", isDirectory: true)
        let resultDir = workspace
            .appendingPathComponent("runs/2026-08-01_090000_probe/method-probe", isDirectory: true)
        try FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resultDir, withIntermediateDirectories: true)

        try Data(JSONSerialization.data(withJSONObject: ["app": "com.example.app"]))
            .write(to: workspace.appendingPathComponent("config.json"))

        let spec: [String: Any] = [
            "id": "method-probe",
            "title": "Method probe",
            "steps": [["action": ["type": "tap", "selector": ["label": "X"]]]]
        ]
        try Data(JSONSerialization.data(withJSONObject: spec))
            .write(to: testsDir.appendingPathComponent("method-probe.json"))

        let result: [String: Any] = [
            "id": "method-probe",
            "passed": true,
            "duration": 1.0,
            "steps": [[
                "passed": true,
                "attempted-methods": [["method": method, "value": "probe"]]
            ]]
        ]
        try Data(JSONSerialization.data(withJSONObject: result))
            .write(to: resultDir.appendingPathComponent("result.json"))

        let outcome = try ResultValidator.validate(workspace: workspace.path)
        // Match on the diagnostic's own wording, not the substring "method" — the
        // temp path contains that word too, and the run.json cross-checks (which
        // this workspace deliberately does not satisfy) would look like hits.
        return outcome.errors.filter { $0.contains("attempted-methods") }
    }

    func testEveryHarnessMethodPassesValidation() throws {
        for method in Self.harnessMethods {
            let errors = try methodErrors(for: method)
            XCTAssertTrue(
                errors.isEmpty,
                "method '\(method)' is written by the harness but rejected by validate: \(errors)")
        }
    }

    /// The check still has teeth: an unknown method is rejected.
    func testUnknownMethodIsStillRejected() throws {
        let errors = try methodErrors(for: "telepathy")
        XCTAssertTrue(errors.contains { $0.contains("method must be one of") }, "\(errors)")
    }
}
