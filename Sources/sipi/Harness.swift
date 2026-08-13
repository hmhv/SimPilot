// Harness.swift
//
// Deterministic SimPilot v2 runner. The skills should create explicit JSON
// specs and call `sipi run-test` / `sipi run-suite` instead of reconstructing a
// Bash loop step by step.

import ArgumentParser
import Foundation
import SimCore
import SimNative
import SimShell

private struct HarnessError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

private struct HarnessConfig: Decodable {
    var app: String?
    var stepDelay: Double?
    var maxRetries: Int?
    var networkConditionProvider: String?

    enum CodingKeys: String, CodingKey {
        case app
        case stepDelay = "step-delay"
        case maxRetries = "max-retries"
        case networkConditionProvider = "network-condition-provider"
    }
}

private enum HarnessJSONValue: Codable {
    case object([String: HarnessJSONValue])
    case array([HarnessJSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([HarnessJSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: HarnessJSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

private struct HarnessTest: Decodable {
    var id: String
    var title: String?
    var app: String?
    var tags: [String]?
    var steps: [HarnessStep]
}

private struct HarnessStep: Decodable {
    var id: String?
    var action: HarnessAction?
    var verify: HarnessVerify?
    var optional: Bool?
    var wait: Double?
    var note: String?
}

private struct HarnessAction: Decodable {
    var type: String
    var selector: HarnessSelector?
    var point: HarnessPoint?
    var text: String?
    var usage: Int?
    var button: String?
    var start: HarnessPoint?
    var end: HarnessPoint?
    var duration: Double?
    // Extended v2 actions (slider/gesture/long-press/key-combo/key-sequence/drag/orientation/crown).
    var value: Double?        // slider target percentage 0...100
    var tolerance: Double?    // slider accepted tolerance, normalized 0...1
    var preset: String?       // gesture preset (scroll-* / swipe-from-*-edge)
    var modifiers: [Int]?     // key-combo modifier keycodes
    var key: Int?             // key-combo target keycode
    var keycodes: [Int]?      // key-sequence keycodes
    var delay: Double?        // key-sequence inter-key delay (seconds)
    var steps: Int?           // drag interpolated move count
    var orientation: String?  // orientation set name
    var delta: Double?        // crown rotation delta
    // Simulator test controls.
    var url: String?              // open-url
    var operation: String?        // privacy/location/status-bar/network-condition
    var service: String?          // privacy service
    var bundleID: String?         // per-action app override
    var latitude: Double?         // location set
    var longitude: Double?        // location set
    var appearance: String?       // appearance light/dark
    var contentSize: String?      // Dynamic Type category
    var enabled: Bool?            // increase-contrast
    var payload: HarnessJSONValue? // push payload
    var profile: String?          // network-condition profile
    var arguments: [String]?      // launch argv or status-bar override args
    var environment: [String: String]? // launch environment (without SIMCTL_CHILD_)
    var inputMethod: String?      // type: paste (default) or keyboard
    var clear: Bool?              // type: empty the field before inserting
    var verifyValue: Bool?        // set-text: confirm the written value (default true)
    var verifyEffect: Bool?       // type: require the AX tree to change (default true)
    // Multi-finger input.
    var direction: String?        // pinch: in | out
    var separation: Double?       // pinch: widest normalized finger separation
    var points: [HarnessPoint]?   // multitouch: exactly two contacts
    var phase: Int?               // multitouch: 1 = begin/move, 2 = end
    // Device state reached through devicectl.
    var settings: HarnessDisplaySettings? // display-state facets

    enum CodingKeys: String, CodingKey {
        case type, selector, point, text, usage, button, start, end, duration
        case value, tolerance, preset, modifiers, key, keycodes, delay, steps, orientation, delta
        case url, operation, service, latitude, longitude, appearance, enabled, payload, profile, arguments, environment, clear
        case direction, separation, points, phase, settings
        case bundleID = "bundle-id"
        case contentSize = "content-size"
        case inputMethod = "input-method"
        case verifyValue = "verify-value"
        case verifyEffect = "verify-effect"
    }
}

/// The `display-state` action's `settings` object: the appearance and
/// accessibility facets devicectl can write. Typed rather than a free-form
/// dictionary so an unknown or misspelled facet is a validation error instead of
/// a silently ignored key.
///
/// Deliberately EXCLUDES light/dark, text size, and Increase Contrast even though
/// devicectl can write all three. Each already has its own action (`appearance`,
/// `content-size`, `increase-contrast`) backed by simctl, and each captures its
/// own restore baseline the first time that action runs. Allowing two mechanisms
/// to move one facet means two independently captured baselines: a test that set
/// light/dark through both would restore whichever ran last and leave the device
/// on the wrong value. One facet, one owner.
private struct HarnessDisplaySettings: Decodable {
    var lookAndFeel: String?
    var reduceMotion: Bool?
    var reduceTransparency: Bool?
    var showBorders: Bool?
    var liquidGlassOpacity: Double?
    var colorFilter: Bool?
    var colorFilterType: String?
    var colorFilterIntensity: Double?
    var largerAccessibilitySizes: Bool?

    enum CodingKeys: String, CodingKey {
        case lookAndFeel = "look-and-feel"
        case reduceMotion = "reduce-motion"
        case reduceTransparency = "reduce-transparency"
        case showBorders = "show-borders"
        case liquidGlassOpacity = "liquid-glass-opacity"
        case colorFilter = "color-filter"
        case colorFilterType = "color-filter-type"
        case colorFilterIntensity = "color-filter-intensity"
        case largerAccessibilitySizes = "larger-accessibility-sizes"
    }

    var appearanceSettings: [AppearanceSetting] {
        var settings: [AppearanceSetting] = []
        if let lookAndFeel { settings.append(.lookAndFeel(lookAndFeel)) }
        if let reduceMotion { settings.append(.reduceMotion(reduceMotion)) }
        if let reduceTransparency { settings.append(.reduceTransparency(reduceTransparency)) }
        if let showBorders { settings.append(.showBorders(showBorders)) }
        if let liquidGlassOpacity { settings.append(.liquidGlassOpacity(liquidGlassOpacity)) }
        if let colorFilter { settings.append(.colorFilter(colorFilter)) }
        if let colorFilterType { settings.append(.colorFilterType(colorFilterType)) }
        if let colorFilterIntensity { settings.append(.colorFilterIntensity(colorFilterIntensity)) }
        if let largerAccessibilitySizes { settings.append(.largerAccessibilitySizes(largerAccessibilitySizes)) }
        return settings
    }

    /// Facet names in the action, for the result's `value` field.
    var summary: String {
        appearanceSettings.compactMap { $0.arguments.first?.replacingOccurrences(of: "--", with: "") }
            .joined(separator: ",")
    }
}

private struct HarnessSelector: Decodable {
    var id: String?
    var label: String?
    var value: String?
    var elementType: String?

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case value
        case elementType = "element-type"
    }
}

private struct HarnessPoint: Decodable {
    var x: Double
    var y: Double
    var unit: String?
}

private struct HarnessVerify: Decodable {
    var contains: [String]?
    var absent: [String]?
    var matches: [String]?
    var notMatches: [String]?
    var elements: [HarnessElementCondition]?

    enum CodingKeys: String, CodingKey {
        case contains, absent, matches, elements
        case notMatches = "not-matches"
    }
}

/// JSON shape of one structured element assertion. Kept separate from
/// `SimCore.ElementCondition` so the wire format's kebab-case keys stay in the
/// harness layer and the evaluator stays a pure value type.
private struct HarnessElementCondition: Decodable {
    var id: String?
    var label: String?
    var value: String?
    var elementType: String?
    var exists: Bool?
    var enabled: Bool?
    var valueEquals: String?
    var valueMatches: String?
    var count: Int?
    var minCount: Int?
    var maxCount: Int?
    var minWidth: Double?
    var minHeight: Double?

    enum CodingKeys: String, CodingKey {
        case id, label, value, exists, enabled, count
        case elementType = "element-type"
        case valueEquals = "value-equals"
        case valueMatches = "value-matches"
        case minCount = "min-count"
        case maxCount = "max-count"
        case minWidth = "min-width"
        case minHeight = "min-height"
    }

    var condition: ElementCondition {
        ElementCondition(
            id: id,
            label: label,
            value: value,
            elementType: elementType,
            exists: exists,
            enabled: enabled,
            valueEquals: valueEquals,
            valueMatches: valueMatches,
            count: count,
            minCount: minCount,
            maxCount: maxCount,
            minWidth: minWidth,
            minHeight: minHeight
        )
    }
}

private struct HarnessSuite: Decodable {
    var name: String
    var tests: [String]
    var settings: HarnessSuiteSettings?
}

private struct HarnessSuiteSettings: Decodable {
    var stopOnFailure: Bool?
    var resetBetweenTests: Bool?

    enum CodingKeys: String, CodingKey {
        case stopOnFailure = "stop-on-failure"
        case resetBetweenTests = "reset-between-tests"
    }
}

private struct HarnessRunOptions {
    var workspace: String
    var udid: String?
    var bundleID: String?
    var runDir: String?
    var retries: Int?
    var launch: Bool
    var suiteName: String?
    var stopOnFailure: Bool
    var resetBetweenTests: Bool
}

private enum HarnessTime {
    static func iso(_ date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func directoryStamp(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter.string(from: date)
    }
}

private final class TraceWriter {
    private let url: URL

    init(path: String) throws {
        url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
    }

    func event(_ event: String, fields: [String: Any] = [:]) {
        var object = fields
        object["time"] = HarnessTime.iso()
        object["event"] = event
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.write(contentsOf: Data("\n".utf8))
        }
    }
}

private final class HarnessRunner {
    // Practical bounds, re-applied here because run-test loads config.json without
    // going through the workspace validator.
    private static let maxRetries = 10
    private static let maxStepDelaySeconds = 60.0

    private let driver = NativeDriver()
    private let fm = FileManager.default
    private let options: HarnessRunOptions
    private let config: HarnessConfig
    private let runDir: String
    private let udid: String
    private let device: Device?
    private let bundleID: String
    private let runTrace: TraceWriter
    private let started = Date()
    private var runEntries: [[String: Any]] = []
    private var initialAppearance: String?
    private var initialContentSize: String?
    private var initialIncreaseContrast: String?
    private var initialDisplayState: AppearanceState?
    private var initialBiometricsEnrolled: Bool?
    private var locationWasModified = false
    private var statusBarWasModified = false
    private var activeNetworkConditionBundleID: String?
    private var environmentWasCleaned = false

    init(options: HarnessRunOptions) throws {
        self.options = options
        self.config = try Self.loadConfig(workspace: options.workspace)
        let resolvedUDID = try Self.resolveUDID(driver: driver, requested: options.udid)
        self.udid = resolvedUDID
        self.device = try? driver.devices().first { $0.udid == resolvedUDID }
        if !SimShell.isBooted(resolvedUDID) {
            try SimShell.boot(udid: resolvedUDID)
        }
        self.bundleID = options.bundleID ?? config.app ?? ""
        guard !self.bundleID.isEmpty else {
            throw HarnessError("Bundle ID is required. Pass --bundle-id or set .simpilot/config.json app.")
        }
        self.runDir = options.runDir ?? Self.defaultRunDir(workspace: options.workspace, device: device)
        try fm.createDirectory(atPath: self.runDir, withIntermediateDirectories: true)
        self.runTrace = try TraceWriter(path: self.runDir + "/trace.jsonl")
        runTrace.event("run-start", fields: ["device": udid, "bundle-id": bundleID])
    }

    /// Validate every spec and reject duplicate ids, returning the loaded tests.
    /// Call this BEFORE constructing a HarnessRunner so an invalid spec (or two
    /// tests sharing an id, which would map to the same <runDir>/<id> output and
    /// silently overwrite each other) fails fast — without booting a simulator or
    /// leaving an empty run directory behind.
    static func preflight(testPaths: [String]) throws -> [HarnessTest] {
        var loaded: [HarnessTest] = []
        var seenIDs = Set<String>()
        var errors: [String] = []
        for path in testPaths {
            let outcome = ResultValidator.validateTestFile(path)
            if !outcome.isValid {
                errors.append(contentsOf: outcome.errors)
                continue
            }
            let test = try loadTest(path: path)
            if !seenIDs.insert(test.id).inserted {
                errors.append("duplicate test id '\(test.id)' in this run; ids must be unique")
                continue
            }
            loaded.append(test)
        }
        if !errors.isEmpty {
            throw HarnessError("pre-flight validation failed:\n  " + errors.joined(separator: "\n  "))
        }
        return loaded
    }

    func run(tests: [HarnessTest]) throws -> String {
        defer {
            if !environmentWasCleaned {
                try? cleanupEnvironment()
            }
        }
        try writeRunJSON(finished: nil)

        for test in tests {
            let result = try run(test: test)
            runEntries.append([
                "id": test.id,
                "passed": result.passed,
                "review": result.review,
                "skipped": result.skipped,
                "duration": result.duration
            ].filterJSON())
            try writeRunJSON(finished: nil)
            // Restore harness-owned simulator state between tests so it starts
            // each test from the captured baseline. Best-effort: a failure is
            // traced and the run continues; the strict end-of-run cleanup retries
            // and surfaces any residue.
            if options.resetBetweenTests {
                resetSimulatorStateBetweenTests()
            }
            if options.stopOnFailure && !result.passed {
                break
            }
        }

        // Finalize the run report before cleanup so a cleanup failure (which is
        // intentionally surfaced as a throw) can never discard run.json,
        // summary.json, or report.html.
        try writeRunJSON(finished: Date())
        try ReportGenerator.writeTestReport(runDir: runDir)
        runTrace.event("run-finish", fields: ["run-dir": runDir])
        try cleanupEnvironment()
        environmentWasCleaned = true
        return runDir
    }

    /// Restore simulator-wide state that the harness owns back to the values it
    /// captured before the first mutation, clearing the associated tracking as
    /// each item succeeds. Permission changes are intentionally not restored
    /// because simctl has no safe readback for their prior authorization state.
    /// Returns the list of restore failures (empty on full success) so callers
    /// decide whether to surface them as a throw or record and continue.
    @discardableResult
    private func restoreSimulatorState() -> [String] {
        var failures: [String] = []

        if let activeNetworkConditionBundleID {
            do {
                let provider = try NetworkConditionProvider.resolve(
                    configuredPath: config.networkConditionProvider
                )
                try provider.clear(udid: udid, bundleID: activeNetworkConditionBundleID)
                self.activeNetworkConditionBundleID = nil
                runTrace.event("network-condition-clear", fields: ["automatic": true])
            } catch {
                failures.append("network condition: \(error)")
            }
        }

        if locationWasModified {
            do { try SimShell.clearLocation(udid: udid); locationWasModified = false }
            catch { failures.append("location: \(error)") }
        }
        if statusBarWasModified {
            do { try SimShell.statusBarClear(udid: udid); statusBarWasModified = false }
            catch { failures.append("status bar: \(error)") }
        }
        if let initialAppearance, ["light", "dark"].contains(initialAppearance) {
            do { try SimShell.setAppearance(udid: udid, appearance: initialAppearance); self.initialAppearance = nil }
            catch { failures.append("appearance: \(error)") }
        }
        if let initialContentSize,
           !["unknown", "unsupported"].contains(initialContentSize) {
            do { try SimShell.setContentSize(udid: udid, contentSize: initialContentSize); self.initialContentSize = nil }
            catch { failures.append("content size: \(error)") }
        }
        if let initialIncreaseContrast,
           ["enabled", "disabled"].contains(initialIncreaseContrast) {
            do {
                try SimShell.setIncreaseContrast(
                    udid: udid,
                    enabled: initialIncreaseContrast == "enabled"
                )
                self.initialIncreaseContrast = nil
            } catch {
                failures.append("increase contrast: \(error)")
            }
        }
        if let initialDisplayState, !initialDisplayState.isEmpty {
            do {
                try DeviceCtl.setAppearance(udid: udid, settings: Self.restoreSettings(for: initialDisplayState))
                self.initialDisplayState = nil
            } catch {
                failures.append("display state: \(error)")
            }
        }
        if let initialBiometricsEnrolled {
            do {
                try DeviceCtl.setBiometricsEnrollment(udid: udid, enabled: initialBiometricsEnrolled)
                self.initialBiometricsEnrolled = nil
            } catch {
                failures.append("biometrics enrollment: \(error)")
            }
        }

        return failures
    }

    /// Turn a captured appearance state back into the writes that restore it.
    ///
    /// Only facets the runtime actually reported are written back: a nil field
    /// means "unsupported / unknown", and writing it as `off` would leave the
    /// device in a state it was never in.
    ///
    /// Restores exactly the facets `display-state` can set — light/dark, text
    /// size, and Increase Contrast are owned by the `appearance`,
    /// `content-size`, and `increase-contrast` actions and restored through their
    /// own captured baselines. Writing them from here too would mean two restores
    /// racing to set one facet from two different baselines.
    private static func restoreSettings(for state: AppearanceState) -> [AppearanceSetting] {
        var settings: [AppearanceSetting] = []
        if let value = state.reduceMotion { settings.append(.reduceMotion(value)) }
        if let value = state.reduceTransparency { settings.append(.reduceTransparency(value)) }
        if let value = state.showBorders { settings.append(.showBorders(value)) }
        if let value = state.liquidGlassOpacity { settings.append(.liquidGlassOpacity(value)) }
        if let value = state.colorFilterEnabled { settings.append(.colorFilter(value)) }
        if let value = state.largerAccessibilitySizes { settings.append(.largerAccessibilitySizes(value)) }
        // The filter kind and intensity survive a disabled filter, so restore them
        // too — otherwise re-enabling the filter later picks up the test's values
        // instead of the user's. Skipped when the runtime reports no kind.
        if let value = state.colorFilterType { settings.append(.colorFilterType(value)) }
        // devicectl REJECTS an intensity alongside the grayscale filter
        // ("--color-filter-intensity is not supported for the grayscale filter
        // type"), and a rejected restore leaves the whole batch unapplied — so
        // the one facet that cannot take an intensity must not be sent one.
        if let value = state.colorFilterIntensity, (0.25...1.0).contains(value),
           state.colorFilterType != "grayscale" {
            settings.append(.colorFilterIntensity(value))
        }
        // Only restorable when the runtime reports a look this build can map back
        // to a settable token; the display name devicectl reports is not the one
        // it accepts.
        if let value = state.restorableLookAndFeel { settings.append(.lookAndFeel(value)) }
        return settings
    }

    /// Facets the action wants to change that the captured baseline cannot restore.
    ///
    /// `restoreSettings(for:)` only writes back facets the runtime reported, so a
    /// facet missing from the baseline is one the run would leave applied. Checking
    /// before the write keeps the "change nothing you cannot put back" rule that
    /// `captureBaseline` starts.
    ///
    /// `color-filter-type` / `color-filter-intensity` are exempt: devicectl reports
    /// them only while the filter is on, and the validator already requires
    /// `color-filter` alongside them — switching the filter back off is what
    /// restores the screen, whatever kind is left configured behind it.
    private static func unrestorableFacets(
        requested: HarnessDisplaySettings?,
        baseline: AppearanceState?
    ) -> Set<String>? {
        guard let requested, let baseline else { return nil }
        var missing: Set<String> = []
        func require(_ present: Bool, _ name: String) {
            if !present { missing.insert(name) }
        }
        if requested.reduceMotion != nil { require(baseline.reduceMotion != nil, "reduce-motion") }
        if requested.reduceTransparency != nil {
            require(baseline.reduceTransparency != nil, "reduce-transparency")
        }
        if requested.showBorders != nil { require(baseline.showBorders != nil, "show-borders") }
        if requested.liquidGlassOpacity != nil {
            require(baseline.liquidGlassOpacity != nil, "liquid-glass-opacity")
        }
        if requested.colorFilter != nil { require(baseline.colorFilterEnabled != nil, "color-filter") }
        if requested.largerAccessibilitySizes != nil {
            require(baseline.largerAccessibilitySizes != nil, "larger-accessibility-sizes")
        }
        if requested.lookAndFeel != nil { require(baseline.restorableLookAndFeel != nil, "look-and-feel") }
        return missing
    }


    /// Capture the restore baseline for a state-changing action, failing the step
    /// when it cannot be read.
    ///
    /// The alternative — proceeding without a baseline — changes the device with
    /// no way to change it back, so the run ends with the test's state still
    /// applied and nothing in the artifacts saying so. A step that cannot
    /// guarantee restoration must not run.
    private func captureBaseline<T>(_ action: String, _ read: () throws -> T) throws -> T {
        do {
            return try read()
        } catch {
            throw HarnessError(
                """
                \(action): could not read the current state to restore afterward (\(error)). \
                Refusing to change the device with no way to put it back.
                """
            )
        }
    }

    /// Guard for the actions that need Xcode 27's simulator-capable devicectl.
    /// Fails the step with an explanation rather than surfacing a raw
    /// device-not-found error from devicectl.
    private func requireSimulatorDeviceCtl(_ action: String) throws {
        guard DeviceCtl.isSimulatorCapable() else {
            throw HarnessError(
                """
                the \(action) action needs a devicectl that can target simulators, which arrived in \
                Xcode 27. This toolchain's devicectl lists no SimulatorCoreDevicePlugin \
                (check `xcrun devicectl list plugins`).
                """
            )
        }
    }

    /// Strict, end-of-run restore. A residual failure is surfaced as a throw so a
    /// leaked condition (e.g. an active network profile) is never silently
    /// ignored — even when every test passed.
    private func cleanupEnvironment() throws {
        let failures = restoreSimulatorState()
        if !failures.isEmpty {
            runTrace.event("environment-cleanup-failed", fields: ["failures": failures])
            throw HarnessError("Environment cleanup failed: " + failures.joined(separator: "; "))
        }
        runTrace.event("environment-cleanup", fields: ["succeeded": true])
    }

    /// Best-effort restore between tests when `reset-between-tests` is enabled, so
    /// state a test set (appearance, Dynamic Type, location, status bar, network
    /// condition) does not leak into the next test. A failure is recorded and the
    /// suite continues; the residual tracking is retried and surfaced by the
    /// strict end-of-run cleanup.
    private func resetSimulatorStateBetweenTests() {
        let failures = restoreSimulatorState()
        if failures.isEmpty {
            runTrace.event("reset-between-tests", fields: ["restored": true])
        } else {
            runTrace.event("reset-between-tests-failed", fields: ["failures": failures])
        }
    }

    private struct TestResult {
        var passed: Bool
        var review: Bool
        var skipped: Bool
        var duration: Double
    }

    private func run(test: HarnessTest) throws -> TestResult {
        let testStarted = Date()
        guard PathSafety.isSafeComponent(test.id) else {
            throw HarnessError("test id '\(test.id)' is not a safe path component")
        }
        let testDir = runDir + "/" + test.id
        try fm.createDirectory(atPath: testDir, withIntermediateDirectories: true)
        let testTrace = try TraceWriter(path: testDir + "/trace.jsonl")
        testTrace.event("test-start", fields: ["test": test.id])

        if options.launch {
            if options.resetBetweenTests {
                try? SimShell.terminate(udid: udid, bundleID: test.app ?? bundleID)
            }
            _ = try SimShell.launch(udid: udid, bundleID: test.app ?? bundleID)
            usleep(700 * 1000)
            // The fixed sleep alone is not enough on every runtime (iOS 27.0 keeps
            // answering with a degenerate tree well past it), so wait for the app
            // to actually be reachable before the first step runs.
            let launchWaitStarted = Date()
            let roots = waitForUsableTree()
            if ChildTree.isDegenerate(roots) {
                testTrace.event("launch-tree-unavailable", fields: [
                    "waited": Date().timeIntervalSince(launchWaitStarted)
                ])
            }
        }

        var stepResults: [[String: Any]] = []
        var failed = false
        var review = false
        let retries = min(Self.maxRetries, max(0, options.retries ?? config.maxRetries ?? 1))

        for (index, step) in test.steps.enumerated() {
            if failed {
                stepResults.append([
                    "passed": true,
                    "skipped": true,
                    "note": "skipped after prior failure"
                ])
                continue
            }

            let result = runStep(
                test: test,
                step: step,
                index: index,
                testDir: testDir,
                retries: retries,
                trace: testTrace
            )
            stepResults.append(result)
            if result["review"] as? Bool == true { review = true }
            if result["passed"] as? Bool != true && result["skipped"] as? Bool != true {
                failed = true
            }
            try writeResultJSON(test: test, testDir: testDir, passed: !failed, review: review, steps: stepResults, started: testStarted)
        }

        let duration = Date().timeIntervalSince(testStarted)
        try writeResultJSON(test: test, testDir: testDir, passed: !failed, review: review, steps: stepResults, started: testStarted)
        testTrace.event("test-finish", fields: ["test": test.id, "passed": !failed, "duration": duration])
        return TestResult(passed: !failed, review: review, skipped: false, duration: duration)
    }

    private func runStep(
        test: HarnessTest,
        step: HarnessStep,
        index: Int,
        testDir: String,
        retries: Int,
        trace: TraceWriter
    ) -> [String: Any] {
        let stepStarted = Date()
        let stepNumber = index + 1
        let screenshotName = String(format: "step-%03d.png", stepNumber)
        let beforeName = String(format: "step-%03d.describe-before.json", stepNumber)
        let afterName = String(format: "step-%03d.describe-after.json", stepNumber)
        trace.event("step-start", fields: ["test": test.id, "step": stepNumber, "step-id": step.id ?? ""])

        do {
            let before = try describeJSON(expect: nil)
            try before.write(toFile: testDir + "/" + beforeName, atomically: true, encoding: .utf8)

            if step.optional == true, let action = step.action, targetIsDefinitelyAbsent(action: action) {
                return [
                    "passed": true,
                    "skipped": true,
                    "duration": Date().timeIntervalSince(stepStarted),
                    "note": "optional target not found"
                ]
            }

            var attempted: [[String: Any]] = []
            var lastFailureType = "verify"
            var verifyRows: [[String: Any]] = []
            var stepPassed = false

            var retryUnsafeNote: String?
            var lastActionError: String?

            for attempt in 0...retries {
                // A throw before verify (resolution, invalid input, HID/sim error)
                // is an `action` failure; a mismatch or error once verification has
                // begun is a `verify` failure.
                var stage = "action"
                // Everything that describes HOW THIS ATTEMPT WENT resets here; the
                // result reports how the step ENDED, so nothing may leak forward
                // from an earlier attempt. Two ways that bit:
                //
                //  - a first-attempt exception pinned an action error onto a step
                //    that later reached verify and failed there, and
                //  - a first-attempt verify mismatch survived into a step whose
                //    retry threw at the action stage, so `failure-type: action`
                //    was reported next to a "Missing Verify" row in the report
                //    and in summary.json.
                //
                // Both are still in the trace. `attempted` is the exception: it
                // deliberately accumulates, because attempted-methods is the log
                // of everything that was tried.
                lastActionError = nil
                verifyRows = []
                do {
                    if let action = step.action {
                        attempted.append(try perform(action: action))
                    }
                    stage = "verify"

                    verifyRows = try waitAndVerify(step.verify, timeout: step.wait ?? 3.0)
                    stepPassed = verifyRows.allSatisfy { $0["found"] as? Bool == true }
                    if stepPassed { break }
                    lastFailureType = "verify"
                    // A mismatch does not throw, so it would otherwise leave no
                    // trace entry — and "every failed attempt is traced" is the
                    // contract `json-reference.md` states.
                    trace.event("step-attempt-error", fields: [
                        "test": test.id, "step": stepNumber, "attempt": attempt,
                        "stage": "verify",
                        "error": StepNote.verifyMismatchSummary(verifyRows)
                    ])
                } catch {
                    lastFailureType = stage
                    // Keep the message, not just the category. `failure-type:
                    // action` alone cannot tell an ambiguous selector from a dead
                    // bridge, and the resolver's error is the part that says which
                    // ("Multiple (3) elements matched label 'Delete'..."). It
                    // matters most for a step whose optional pre-resolution
                    // declined and fell through to here: without this the reason it
                    // declined never reaches the result.
                    lastActionError = String(describing: error)
                    trace.event("step-attempt-error", fields: [
                        "test": test.id, "step": stepNumber, "attempt": attempt,
                        "stage": stage, "error": lastActionError ?? ""
                    ])
                    // Some failures happen AFTER the action reached the device —
                    // text that was sent but whose outcome could not be read back is
                    // the case in hand. Re-running the action would repeat the side
                    // effect (typing the string twice), so the step ends here and
                    // says why in the result.
                    if let advising = error as? RetryAdvisingError, !advising.retrySafe {
                        retryUnsafeNote = String(describing: error)
                        trace.event("step-retry-suppressed", fields: [
                            "test": test.id, "step": stepNumber, "reason": String(describing: error)
                        ])
                        break
                    }
                }
                if attempt < retries {
                    trace.event("step-retry", fields: ["test": test.id, "step": stepNumber, "attempt": attempt + 1])
                    // Honor an explicit step-delay of 0 (no pause), matching the
                    // validator's 0...60 range; only an unset value defaults to 0.3.
                    sleepSeconds(min(Self.maxStepDelaySeconds, max(0, config.stepDelay ?? 0.3)))
                }
            }

            // The after-artifacts are EVIDENCE, not the verdict — which is already
            // decided above. Capturing them best-effort keeps a step's conclusion
            // and its reasoning in `result.json` even when the device cannot answer
            // any more. That matters most in exactly the case where it is likeliest
            // to fail: a stalled accessibility bridge is both why the step could not
            // be verified and why the after-describe throws, and letting it escape
            // would replace the "text was sent, do not blindly retry" note with a
            // generic capture error.
            // Two outcomes tracked separately, because they answer different
            // questions: `after` is the tree text (used for the inline snapshot,
            // which needs no file) and `afterFileWritten` says whether the file
            // that `screenshots.after` would point at actually exists. Reading the
            // tree can succeed while writing it fails — a full disk, a read-only
            // run directory — and referencing a file that was never written is
            // worse than omitting the reference.
            var artifactErrors: [String] = []
            var after = ""
            var afterFileWritten = false
            do {
                let captured = try describeJSON(expect: firstExpectedString(step.verify))
                after = captured
                try captured.write(toFile: testDir + "/" + afterName, atomically: true, encoding: .utf8)
                afterFileWritten = true
            } catch {
                artifactErrors.append("after describe-ui: \(error)")
            }
            var screenshotCaptured = true
            do {
                try driver.screenshot(to: URL(fileURLWithPath: testDir + "/" + screenshotName), udid: udid)
            } catch {
                screenshotCaptured = false
                artifactErrors.append("after screenshot: \(error)")
            }

            var result: [String: Any] = [
                "passed": stepPassed,
                "duration": Date().timeIntervalSince(stepStarted),
                "verify": verifyRows,
                "attempted-methods": attempted
            ]
            // Reference only the artifacts that exist; a path to a file that was
            // never written is worse than its absence.
            if screenshotCaptured { result["screenshot"] = screenshotName }
            var screenshots: [String: String] = ["before": beforeName]
            if afterFileWritten { screenshots["after"] = afterName }
            result["screenshots"] = screenshots
            if let action = step.action { result["action"] = actionDescription(action) }
            // The suppressed-retry reason is the more actionable note: it explains
            // both the failure and why the harness did not try again. Artifact
            // failures are appended rather than allowed to displace it.
            let notes = StepNote.compose(
                retryUnsafeNote: retryUnsafeNote,
                stepNote: step.note,
                lastActionError: lastActionError,
                artifactErrors: artifactErrors,
                passed: stepPassed
            )
            if !notes.isEmpty { result["note"] = notes }
            if !stepPassed {
                result["failure-type"] = lastFailureType
                if !after.isEmpty {
                    result["describe-ui-snapshot"] = String(after.split(separator: "\n").prefix(50).joined(separator: "\n"))
                }
            }
            trace.event("step-finish", fields: ["test": test.id, "step": stepNumber, "passed": stepPassed])
            return result.filterJSON()
        } catch {
            trace.event("step-error", fields: ["test": test.id, "step": stepNumber, "error": String(describing: error)])
            return [
                "passed": false,
                "duration": Date().timeIntervalSince(stepStarted),
                "failure-type": "action",
                "note": String(describing: error),
                "attempted-methods": []
            ]
        }
    }

    private func perform(action: HarnessAction) throws -> [String: Any] {
        switch action.type {
        case "tap":
            if let selector = action.selector {
                try driver.tap(try resolveSelectorPoint(selector), udid: udid)
                return attemptedMethod(for: selector)
            }
            guard let pointSpec = action.point else { throw HarnessError("tap action requires selector or point.") }
            let point = try normalizedPoint(pointSpec)
            try driver.tap(point, udid: udid)
            return ["method": "touch-coordinate", "value": "\(pointSpec.x),\(pointSpec.y)"]

        case "double-tap":
            if let selector = action.selector {
                try DoubleTapInput.perform(try resolveSelectorPoint(selector), driver: driver, udid: udid)
                return attemptedMethod(for: selector)
            }
            guard let pointSpec = action.point else { throw HarnessError("double-tap action requires selector or point.") }
            try DoubleTapInput.perform(try normalizedPoint(pointSpec), driver: driver, udid: udid)
            return ["method": "touch-coordinate", "value": "\(pointSpec.x),\(pointSpec.y)"]

        case "pinch":
            guard let direction = action.direction, let pinchDirection = PinchDirection(rawValue: direction) else {
                throw HarnessError(
                    "pinch action requires direction: "
                    + PinchDirection.allCases.map(\.rawValue).joined(separator: " or ") + ".")
            }
            // Center defaults to the middle of the screen, matching `sipi pinch`.
            let center = try action.point.map(normalizedPoint) ?? Point(x: 0.5, y: 0.5)
            let separation = action.separation ?? PinchPlan.defaultSeparation
            let steps = action.steps ?? PinchPlan.defaultSteps
            let duration = action.duration ?? 0.5
            let plan: PinchPlan
            do {
                plan = try PinchPlan.make(
                    center: center, separation: separation, direction: pinchDirection, steps: steps)
            } catch let error as PinchPlanError {
                throw HarnessError(error.description)
            }
            // One driver call for the whole gesture — see `multiTouchSequence`:
            // per-frame calls re-resolve the orientation and AX extent and stall a
            // rotated pinch past the point the guest still recognizes it.
            try driver.multiTouchSequence(
                plan.frames,
                frameDelay: PinchPlan.frameDelay(duration: duration, steps: steps),
                udid: udid
            )
            return ["method": "multitouch", "value": "pinch-\(direction)"]

        case "multitouch":
            guard let points = action.points, points.count == 2 else {
                throw HarnessError("multitouch action requires exactly two points.")
            }
            guard let phaseValue = action.phase, let phase = TouchPhase(rawValue: phaseValue) else {
                throw HarnessError("multitouch action requires phase 1 (begin/move) or 2 (end).")
            }
            let a = try normalizedPoint(points[0])
            let b = try normalizedPoint(points[1])
            try driver.multiTouch(a, b, phase: phase, udid: udid)
            return ["method": "multitouch", "value": "phase:\(phaseValue)"]

        case "long-press":
            let hold = action.duration ?? 0.5
            if let selector = action.selector {
                try driver.longPress(try resolveSelectorPoint(selector), hold: hold, udid: udid)
                return attemptedMethod(for: selector)
            }
            guard let pointSpec = action.point else { throw HarnessError("long-press action requires selector or point.") }
            try driver.longPress(try normalizedPoint(pointSpec), hold: hold, udid: udid)
            return ["method": "touch-coordinate", "value": "\(pointSpec.x),\(pointSpec.y)"]

        case "type":
            guard let text = action.text else { throw HarnessError("type action requires text.") }
            let method = try resolveInputMethod(action.inputMethod)
            let clear = action.clear ?? false
            // `verify-effect` defaults on: a runtime that drops keyboard HID would
            // otherwise let the step pass while the app never received the text.
            try TextInput.insert(
                text,
                method: method,
                clear: clear,
                driver: driver,
                udid: udid,
                verifyEffect: action.verifyEffect ?? true
            )
            return ["method": "input", "value": clear ? "\(method.rawValue)+clear" : method.rawValue]

        case "set-text":
            return try performSetText(action)

        case "key":
            guard let usage = action.usage else { throw HarnessError("key action requires usage.") }
            try validateKeycodes([usage])
            for event in KeyInput.keyPress(usage: usage) {
                try driver.key(usage: event.usage, down: event.down, udid: udid)
            }
            return ["method": "input", "value": "key:\(usage)"]

        case "key-combo":
            guard let modifiers = action.modifiers, !modifiers.isEmpty, let key = action.key else {
                throw HarnessError("key-combo action requires modifiers and key.")
            }
            try validateKeycodes(modifiers + [key])
            for event in KeyInput.keyCombo(modifiers: modifiers, key: key) {
                try driver.key(usage: event.usage, down: event.down, udid: udid)
            }
            return ["method": "input", "value": "key-combo:\(modifiers.map(String.init).joined(separator: "+"))+\(key)"]

        case "key-sequence":
            guard let keycodes = action.keycodes, !keycodes.isEmpty else {
                throw HarnessError("key-sequence action requires keycodes.")
            }
            try validateKeycodes(keycodes)
            let keyDelay = max(0, action.delay ?? 0.1)
            for (i, code) in keycodes.enumerated() {
                try driver.key(usage: code, down: true, udid: udid)
                try driver.key(usage: code, down: false, udid: udid)
                if i < keycodes.count - 1, keyDelay > 0 { sleepSeconds(keyDelay) }
            }
            return ["method": "input", "value": "key-sequence:\(keycodes.count)"]

        case "button":
            guard let name = action.button, let button = HardwareButton(rawValue: name) else {
                throw HarnessError("button action requires a valid button.")
            }
            try driver.button(button, udid: udid)
            return ["method": "input", "value": "button:\(button.rawValue)"]

        case "swipe":
            guard let start = action.start, let end = action.end else { throw HarnessError("swipe action requires start and end.") }
            try driver.swipe(try normalizedPoint(start), try normalizedPoint(end), duration: action.duration ?? 0.3, udid: udid)
            return ["method": "touch-coordinate", "value": "\(start.x),\(start.y)->\(end.x),\(end.y)"]

        case "drag":
            guard let start = action.start, let end = action.end else { throw HarnessError("drag action requires start and end.") }
            let steps = max(1, min(1000, action.steps ?? 60))
            try driver.compositeDrag(
                from: try normalizedPoint(start),
                to: try normalizedPoint(end),
                duration: action.duration ?? 0.6,
                steps: steps,
                initialHold: 0.05,
                finalHold: 0.05,
                udid: udid
            )
            return ["method": "touch-coordinate", "value": "drag \(start.x),\(start.y)->\(end.x),\(end.y)"]

        case "gesture":
            guard let presetName = action.preset, let gesture = GesturePreset(rawValue: presetName) else {
                let valid = GesturePreset.allCases.map(\.rawValue).joined(separator: ", ")
                throw HarnessError("gesture action requires a valid preset. Valid: \(valid).")
            }
            let endpoints = gesture.normalizedEndpoints()
            try driver.swipe(endpoints.start, endpoints.end, duration: action.duration ?? gesture.defaultDuration, udid: udid)
            return ["method": "touch-coordinate", "value": "gesture:\(presetName)"]

        case "slider":
            return try performSlider(action)

        case "orientation":
            guard let name = action.orientation, let orientation = OrientationSetName(name) else {
                throw HarnessError("orientation action requires a valid orientation (\(OrientationSetName.acceptedNames)).")
            }
            try driver.setOrientation(orientation, udid: udid)
            return ["method": "input", "value": "orientation:\(name)"]

        case "open-url":
            guard let url = action.url, URL(string: url)?.scheme != nil else {
                throw HarnessError("open-url action requires an absolute URL.")
            }
            try SimShell.openURL(udid: udid, url: url)
            return ["method": "simctl", "value": "open-url:\(url)"]

        case "privacy":
            guard let operation = action.operation,
                  ["grant", "revoke", "reset"].contains(operation),
                  let service = action.service, !service.isEmpty else {
                throw HarnessError("privacy action requires operation (grant/revoke/reset) and service.")
            }
            let targetBundleID = action.bundleID ?? bundleID
            switch operation {
            case "grant": try SimShell.grantPrivacy(udid: udid, service: service, bundleID: targetBundleID)
            case "revoke": try SimShell.revokePrivacy(udid: udid, service: service, bundleID: targetBundleID)
            default:
                try SimShell.resetPrivacy(
                    udid: udid,
                    service: service,
                    bundleID: targetBundleID
                )
            }
            return ["method": "simctl", "value": "privacy:\(operation):\(service)"]

        case "push":
            guard let payload = action.payload else {
                throw HarnessError("push action requires an inline payload object.")
            }
            let payloadData = try JSONEncoder().encode(payload)
            guard payloadData.count <= 4096 else {
                throw HarnessError("push payload must not exceed 4096 bytes.")
            }
            let pushTarget = action.bundleID ?? bundleID
            warnIfSilentPushCannotWake(payload: payloadData, udid: udid, bundleID: pushTarget)
            try SimShell.push(
                udid: udid,
                bundleID: pushTarget,
                payload: payloadData
            )
            return ["method": "simctl", "value": "push"]

        case "location":
            guard let operation = action.operation, ["set", "clear"].contains(operation) else {
                throw HarnessError("location action requires operation set or clear.")
            }
            if operation == "clear" {
                try SimShell.clearLocation(udid: udid)
                locationWasModified = false
            } else {
                guard let latitude = action.latitude, let longitude = action.longitude else {
                    throw HarnessError("location set requires latitude and longitude.")
                }
                try SimShell.setLocation(udid: udid, latitude: latitude, longitude: longitude)
                locationWasModified = true
            }
            return ["method": "simctl", "value": "location:\(operation)"]

        case "appearance":
            guard let appearance = action.appearance, ["light", "dark"].contains(appearance) else {
                throw HarnessError("appearance action requires light or dark.")
            }
            if initialAppearance == nil { initialAppearance = try SimShell.appearance(udid: udid) }
            try SimShell.setAppearance(udid: udid, appearance: appearance)
            return ["method": "simctl", "value": "appearance:\(appearance)"]

        case "content-size":
            guard let contentSize = action.contentSize, !contentSize.isEmpty else {
                throw HarnessError("content-size action requires content-size.")
            }
            if initialContentSize == nil { initialContentSize = try SimShell.contentSize(udid: udid) }
            try SimShell.setContentSize(udid: udid, contentSize: contentSize)
            return ["method": "simctl", "value": "content-size:\(contentSize)"]

        case "increase-contrast":
            guard let enabled = action.enabled else {
                throw HarnessError("increase-contrast action requires enabled.")
            }
            if initialIncreaseContrast == nil {
                initialIncreaseContrast = try SimShell.increaseContrast(udid: udid)
            }
            try SimShell.setIncreaseContrast(udid: udid, enabled: enabled)
            return ["method": "simctl", "value": "increase-contrast:\(enabled)"]

        case "display-state":
            // The accessibility appearance facets simctl never exposed (reduce
            // motion, reduce transparency, show borders, color filters, Liquid
            // Glass opacity, Larger Accessibility Sizes). One devicectl call sets
            // them all; the whole state is captured once per run and restored after.
            let facets = action.settings?.appearanceSettings ?? []
            guard !facets.isEmpty else {
                throw HarnessError("display-state action requires settings with at least one facet.")
            }
            try requireSimulatorDeviceCtl("display-state")
            // The baseline is the ONLY way this state gets restored, so a failed
            // read must fail the step. Swallowing it (`try?`) would change the
            // device and leave nothing to change it back with — the run would end
            // with reduce-motion or a color filter still on. It also gates the
            // look-and-feel check below.
            if initialDisplayState == nil {
                initialDisplayState = try captureBaseline("display-state") {
                    try DeviceCtl.appearanceState(udid: udid)
                }
            }
            // devicectl exits 0 for `--look-and-feel` on a runtime that offers
            // only one look (iOS 27 has just "Liquid Glass"), so the write reads
            // as a success while nothing changes. Fail the step instead of
            // recording a state the device never entered.
            if action.settings?.lookAndFeel != nil,
               let state = initialDisplayState, !state.supportsLookAndFeelSwitching {
                throw HarnessError(
                    """
                    look-and-feel cannot be set on this runtime: it offers only \
                    \(state.supportedLooksAndFeels.joined(separator: ", ")). devicectl accepts the write \
                    and ignores it, so the step would pass without changing anything.
                    """
                )
            }
            // A baseline that READ successfully is not automatically a baseline
            // that can RESTORE: a runtime may simply not report a facet this
            // action wants to change. Writing it anyway would leave it applied for
            // the rest of the run, because the restore only writes back facets it
            // actually captured.
            if let unrestorable = Self.unrestorableFacets(
                requested: action.settings, baseline: initialDisplayState
            ), !unrestorable.isEmpty {
                throw HarnessError(
                    """
                    display-state: this runtime does not report \(unrestorable.sorted().joined(separator: ", ")), \
                    so there is no value to restore afterward. Refusing to change a facet the run cannot put back.
                    """
                )
            }
            // A reported value is not automatically a WRITABLE one. The
            // kind/intensity pair is exempt from the check above only because a
            // baseline with the filter OFF is restored by switching it off. With
            // the filter already ON, the restore has to write back whichever of
            // the pair this step changes — so ask about exactly those facets,
            // not about the baseline in the abstract. A step that leaves the
            // pair alone needs nothing from the restore.
            //
            // The blocker carries its own consequence, because they differ: most
            // leave the SCREEN wrong, while a grayscale baseline comes back
            // looking right and leaks only the stored intensity.
            if let requested = action.settings, let baseline = initialDisplayState,
               let blocker = baseline.colorFilterRestoreBlocker(
                   changingType: requested.colorFilterType != nil,
                   changingIntensity: requested.colorFilterIntensity != nil
               ) {
                throw HarnessError(
                    """
                    display-state: \(blocker). Refusing to change a facet the run cannot restore — turn \
                    the device's colour filter off, set it to a restorable value, or use a disposable \
                    simulator.
                    """
                )
            }
            try DeviceCtl.setAppearance(udid: udid, settings: facets)
            return ["method": "devicectl", "value": "display-state:\(action.settings?.summary ?? "")"]

        case "biometrics":
            guard let operation = action.operation,
                  ["enroll", "unenroll", "match", "no-match"].contains(operation) else {
                throw HarnessError("biometrics action requires operation enroll, unenroll, match, or no-match.")
            }
            try requireSimulatorDeviceCtl("biometrics")
            switch operation {
            case "enroll", "unenroll":
                // Enrollment is device state, so capture the baseline for restore.
                // Match events are transient and need no restore.
                if initialBiometricsEnrolled == nil {
                    initialBiometricsEnrolled = try captureBaseline("biometrics") {
                        let state = try DeviceCtl.biometricsEnrollment(udid: udid)
                        guard !state.isEmpty else {
                            throw HarnessError("this device reports no biometric hardware")
                        }
                        return state.values.allSatisfy { $0 }
                    }
                }
                try DeviceCtl.setBiometricsEnrollment(udid: udid, enabled: operation == "enroll")
            default:
                try DeviceCtl.simulateBiometrics(udid: udid, success: operation == "match")
            }
            return ["method": "devicectl", "value": "biometrics:\(operation)"]

        case "status-bar":
            guard let operation = action.operation, ["override", "clear"].contains(operation) else {
                throw HarnessError("status-bar action requires operation override or clear.")
            }
            if operation == "clear" {
                try SimShell.statusBarClear(udid: udid)
                statusBarWasModified = false
            } else {
                guard let arguments = action.arguments, !arguments.isEmpty else {
                    throw HarnessError("status-bar override requires arguments.")
                }
                try SimShell.statusBarOverride(udid: udid, arguments: arguments)
                statusBarWasModified = true
            }
            return ["method": "simctl", "value": "status-bar:\(operation)"]

        case "launch":
            let targetBundleID = action.bundleID ?? bundleID
            _ = try SimShell.launch(
                udid: udid,
                bundleID: targetBundleID,
                arguments: action.arguments ?? [],
                environment: action.environment ?? [:],
                terminateRunning: true
            )
            // Same reason as the pre-test launch: don't hand the next step a tree
            // the app has not populated yet.
            waitForUsableTree()
            return ["method": "simctl", "value": "launch:\(targetBundleID)"]

        case "terminate":
            let targetBundleID = action.bundleID ?? bundleID
            try SimShell.terminate(udid: udid, bundleID: targetBundleID)
            return ["method": "simctl", "value": "terminate:\(targetBundleID)"]

        case "network-condition":
            guard let operation = action.operation, ["apply", "clear"].contains(operation) else {
                throw HarnessError("network-condition action requires operation apply or clear.")
            }
            let targetBundleID = action.bundleID ?? bundleID
            let provider = try NetworkConditionProvider.resolve(
                configuredPath: config.networkConditionProvider
            )
            if operation == "clear" {
                try provider.clear(udid: udid, bundleID: targetBundleID)
                // Only drop tracking when this clear targets the bundle that
                // actually holds the active condition; clearing a different
                // bundle must not skip end-of-run cleanup of the real one.
                if activeNetworkConditionBundleID == targetBundleID {
                    activeNetworkConditionBundleID = nil
                }
                runTrace.event("network-condition-clear", fields: ["bundle-id": targetBundleID])
            } else {
                guard let profile = action.profile else {
                    throw HarnessError("network-condition apply requires profile.")
                }
                if let activeNetworkConditionBundleID,
                   activeNetworkConditionBundleID != targetBundleID {
                    try provider.clear(udid: udid, bundleID: activeNetworkConditionBundleID)
                }
                // Track before invoking the provider so automatic cleanup still
                // clears a condition when apply partially succeeds but exits nonzero.
                activeNetworkConditionBundleID = targetBundleID
                try provider.apply(profile: profile, udid: udid, bundleID: targetBundleID)
                runTrace.event("network-condition-apply", fields: ["bundle-id": targetBundleID, "profile": profile])
            }
            return ["method": "network-condition", "value": operation]

        case "crown":
            guard let delta = action.delta else { throw HarnessError("crown action requires delta.") }
            try driver.crown(delta: delta, udid: udid)
            return ["method": "input", "value": "crown:\(delta)"]

        case "wait":
            sleepSeconds(max(0, action.duration ?? 1.0))
            return ["method": "input", "value": "wait"]

        default:
            throw HarnessError("Unsupported action type '\(action.type)'.")
        }
    }

    /// Resolve a selector to a normalized activation point against the fast tree,
    /// re-fetching the deep grid on a not-found. Shared by `tap` and `long-press`.
    private func resolveSelectorPoint(_ selector: HarnessSelector) throws -> Point {
        let query = try accessibilityQuery(selector)
        let roots = try resolvingRoots(query: query, elementType: selector.elementType)
        let resolution = try AccessibilityTargetResolver.resolveTap(roots: roots, query: query, elementType: selector.elementType)
        guard let frame = screenFrame(of: roots), let point = normalized(resolution.point, in: frame) else {
            throw HarnessError("Could not normalize the resolved point.")
        }
        return point
    }

    /// The resolved element's activation point in LOGICAL coordinates (the
    /// describe-ui / accessibility space), with the screen frame that resolution
    /// already fetched. `set-text` writes through the accessibility bridge, which
    /// addresses elements in that space, so it must not go through the normalized
    /// HID conversion `resolveSelectorPoint` does.
    private func resolveSelectorLogicalPoint(_ selector: HarnessSelector) throws -> ResolvedTarget {
        let query = try accessibilityQuery(selector)
        let roots = try resolvingRoots(query: query, elementType: selector.elementType)
        return ResolvedTarget(
            point: try AccessibilityTargetResolver.resolveTap(
                roots: roots, query: query, elementType: selector.elementType
            ).point,
            screen: screenFrame(of: roots)
        )
    }

    /// Convert an action's normalized/pixel point spec into a LOGICAL point.
    private func logicalPoint(_ spec: HarnessPoint) throws -> ResolvedTarget {
        let normalizedSpec = try normalizedPoint(spec)
        let roots = try driver.describe(udid, deep: false)
        guard let frame = screenFrame(of: roots) else {
            throw HarnessError("Could not determine the screen frame to convert the point.")
        }
        return ResolvedTarget(
            point: Point(
                x: frame.x + normalizedSpec.x * frame.width,
                y: frame.y + normalizedSpec.y * frame.height
            ),
            screen: frame
        )
    }

    /// Write text straight into a field's accessibility value — no keyboard, no
    /// pasteboard, no focus. The write is confirmed by re-reading the element in a
    /// FRESH process (see `guestValue`): the writing process's translator can echo
    /// its own write back, so an in-process read would let a step "pass" against an
    /// element that never accepted the text.
    private func performSetText(_ action: HarnessAction) throws -> [String: Any] {
        guard let text = action.text else { throw HarnessError("set-text action requires text.") }
        let target: ResolvedTarget
        var method = "set-text"
        if let selector = action.selector {
            target = try resolveSelectorLogicalPoint(selector)
            if let id = selector.id { method = "set-text:id:\(id)" }
        } else if let pointSpec = action.point {
            target = try logicalPoint(pointSpec)
            method = "set-text:point"
        } else {
            throw HarnessError("set-text action requires selector or point.")
        }

        try driver.setValue(text, at: target.point, udid: udid)

        // Confirming the write is the default, because an element that ignores it
        // still accepts the setter. `"verify-value": false` is the escape hatch for
        // a field that deliberately reports something else — a SecureField answers
        // with bullets (measured: an 11-character write reads back as
        // "•••••••••••"), and a formatter can rewrite what it was given. The
        // recorded method says which of the two ran, so the artifact never implies
        // a confirmation that did not happen.
        guard action.verifyValue ?? true else {
            return ["method": "input", "value": method + "+unverified"]
        }

        let outcome = verifySetText(
            udid: udid, at: target.point, expected: text, screen: target.screen
        )
        if case .mismatch = outcome {
            throw HarnessError(
                "set-text did not take: wrote '\(text)', the app reports "
                + "\(outcome.observedDescription). Only editable text elements accept a value write; "
                + "for a field that intentionally reports something else (secure field, formatter) "
                + "set \"verify-value\": false and assert on the app's own output instead."
            )
        }
        return ["method": "input", "value": method]
    }

    private func validateKeycodes(_ codes: [Int]) throws {
        for code in codes where !(0...255).contains(code) {
            throw HarnessError("keycodes must be between 0 and 255 (got \(code)).")
        }
    }

    /// Resolve a slider, drag its thumb to `value` (0...100), and poll AXValue to
    /// confirm it landed within tolerance. Mirrors `sipi slider` over the driver.
    private func performSlider(_ action: HarnessAction) throws -> [String: Any] {
        guard let selector = action.selector, selector.id != nil || selector.label != nil else {
            throw HarnessError("slider action requires a selector with id or label.")
        }
        guard let value = action.value else { throw HarnessError("slider action requires value (0...100).") }
        guard value.isFinite, (0...100).contains(value) else {
            throw HarnessError("slider value must be a finite number between 0 and 100 (got \(value)).")
        }
        if let tol = action.tolerance, !(tol > 0 && tol <= 1) {
            throw HarnessError("slider tolerance must be greater than 0 and at most 1 (got \(tol)).")
        }
        let query: AccessibilityQuery = selector.id.map { .id($0) } ?? .label(selector.label!)
        let targetNormalized = value / 100.0
        let tol = action.tolerance ?? SliderPlan.valueTolerance

        let fast = try driver.describe(udid, deep: false)
        let roots: [AXNode]
        do {
            _ = try AccessibilityTargetResolver.resolveElement(roots: fast, query: query, elementType: selector.elementType)
            roots = fast
        } catch let error as ElementResolutionError where error.isNotFound {
            roots = try driver.describe(udid, deep: true)
        }

        let match = try AccessibilityTargetResolver.resolveElement(roots: roots, query: query, elementType: selector.elementType)
        let plan = try SliderPlan.makeDragPlan(
            element: match.element,
            applicationFrame: match.applicationFrame,
            targetNormalized: targetNormalized,
            tolerance: tol
        )
        guard let screen = screenSizeFor(roots: roots) else {
            throw HarnessError("Could not determine the screen size for the slider drag.")
        }

        if !plan.alreadyAtTarget {
            let start = clamp01(Point(x: plan.logicalStart.x / screen.width, y: plan.logicalStart.y / screen.height))
            let end = clamp01(Point(x: plan.logicalEnd.x / screen.width, y: plan.logicalEnd.y / screen.height))
            try driver.compositeDrag(
                from: start,
                to: end,
                duration: SliderPlan.dragDuration,
                steps: SliderPlan.dragSteps,
                initialHold: SliderPlan.dragInitialHold,
                finalHold: SliderPlan.dragFinalHold,
                udid: udid
            )
        }

        let observed = try pollSliderValue(query: query, elementType: selector.elementType, targetNormalized: targetNormalized, tolerance: tol)
        guard let observed, SliderPlan.isWithinTolerance(observed: observed, target: targetNormalized, tolerance: tol) else {
            throw HarnessError("slider did not reach \(SliderPlan.formatPercent(value)) (observed \(observed.map { SliderPlan.formatNormalized($0) } ?? "none")).")
        }
        if let id = selector.id { return ["method": "tap-id", "value": "slider \(id)=\(value)"] }
        return ["method": "tap-label", "value": "slider \(selector.label ?? "")=\(value)"]
    }

    private func pollSliderValue(query: AccessibilityQuery, elementType: String?, targetNormalized: Double, tolerance: Double) throws -> Double? {
        let deadline = Date().addingTimeInterval(SliderPlan.verificationTimeout)
        var last: Double?
        repeat {
            let roots = try driver.describe(udid, deep: false)
            if let match = try? AccessibilityTargetResolver.resolveElement(roots: roots, query: query, elementType: elementType),
               let normalized = try? SliderPlan.parseNormalizedAXValue(match.element.AXValue) {
                last = normalized
                if SliderPlan.isWithinTolerance(observed: normalized, target: targetNormalized, tolerance: tolerance) {
                    return normalized
                }
            }
            usleep(useconds_t(SliderPlan.verificationPollInterval * 1_000_000))
        } while Date() < deadline
        return last
    }

    private func screenSizeFor(roots: [AXNode]) -> ScreenSize? {
        guard let frame = screenFrame(of: roots), frame.width > 0, frame.height > 0 else { return nil }
        return ScreenSize(width: frame.width, height: frame.height)
    }

    private func clamp01(_ p: Point) -> Point {
        Point(x: min(max(p.x, 0), 1), y: min(max(p.y, 0), 1))
    }

    /// Whether an `optional` step's target is DEFINITIVELY absent — the one
    /// condition that may turn the step into a passing skip. A malformed
    /// selector is a real defect, not an absent target, so it does not skip.
    private func targetIsDefinitelyAbsent(action: HarnessAction) -> Bool {
        guard OptionalStepSkip.skippableActionTypes.contains(action.type),
              let selector = action.selector,
              let query = try? accessibilityQuery(selector) else { return false }
        return OptionalStepSkip.targetIsDefinitelyAbsent { deep in
            try self.resolvesTarget(query: query, elementType: selector.elementType, deep: deep)
        }
    }

    /// True when the selector resolves, false when the tree definitively does not
    /// contain it. Any other outcome throws so the caller can tell "absent" apart
    /// from "could not tell".
    ///
    /// A degenerate tree is the important case. Right after a launch the bridge
    /// answers with a single empty root, and resolving against it reports every
    /// selector as missing — which for an `optional` step would mean a passing
    /// skip for an element that is simply not up yet. So wait it out the same way
    /// `resolvingRoots` does, and if it never becomes usable, throw rather than
    /// call the target absent.
    private func resolvesTarget(query: AccessibilityQuery, elementType: String?, deep: Bool) throws -> Bool {
        var roots = try driver.describe(udid, deep: deep)
        if !deep, ChildTree.isDegenerate(roots) {
            roots = waitForUsableTree()
        }
        guard !ChildTree.isDegenerate(roots) else {
            throw HarnessError(
                "accessibility tree is still degenerate; cannot tell whether the target is absent"
            )
        }
        do {
            _ = try AccessibilityTargetResolver.resolveElement(
                roots: roots,
                query: query,
                elementType: elementType
            )
            return true
        } catch let error as ElementResolutionError where error.isNotFound {
            return false
        }
    }

    private func waitAndVerify(_ verify: HarnessVerify?, timeout: Double) throws -> [[String: Any]] {
        guard let verify else { return [] }
        let contains = verify.contains ?? []
        let absent = verify.absent ?? []
        let matches = verify.matches ?? []
        let notMatches = verify.notMatches ?? []
        let elements = (verify.elements ?? []).map(\.condition)
        let deadline = Date().addingTimeInterval(max(0, timeout))
        var rows: [VerifyEvaluator.Row] = []
        repeat {
            // Absence-shaped conditions are evaluated against the deep tree (see
            // VerifyEvaluator): a forbidden string only in System UI / the grid
            // pass must not be missed. Presence escalates to deep on demand.
            let fastNodes = try driver.describe(udid, deep: false)
            let fast = VerifyEvaluator.Capture(json: try AXNodeJSON.string(for: fastNodes), nodes: fastNodes)
            rows = try VerifyEvaluator.evaluate(
                contains: contains,
                absent: absent,
                matches: matches,
                notMatches: notMatches,
                elements: elements,
                fast: fast
            ) {
                let deepNodes = try self.driver.describe(self.udid, deep: true)
                return VerifyEvaluator.Capture(json: try AXNodeJSON.string(for: deepNodes), nodes: deepNodes)
            }
            if rows.allSatisfy({ $0.found }) {
                return rows.map(Self.verifyRowDict)
            }
            usleep(250 * 1000)
        } while Date() < deadline
        return rows.map(Self.verifyRowDict)
    }

    private static func verifyRowDict(_ row: VerifyEvaluator.Row) -> [String: Any] {
        ["check": row.check, "found": row.found, "grep-match": row.grepMatch ?? NSNull()]
    }

    /// Sleep for `seconds`, clamped to a non-negative, in-range microsecond count
    /// so a huge or negative value can never trap the `UInt32` conversion.
    private func sleepSeconds(_ seconds: Double) {
        let micros = (seconds * 1_000_000).rounded()
        usleep(UInt32(min(max(micros, 0), Double(UInt32.max))))
    }

    /// A silent push (`aps.content-available: 1` with no `alert`) only reaches an
    /// app that declares the `remote-notification` background mode: without it iOS
    /// drops the wake, the app never runs, and the step reads as an unexplained
    /// no-op even though `simctl push` succeeded. Warn — never fail — when the
    /// INSTALLED app's Info.plist lacks the mode, and name the two ways out.
    /// Stays silent when the plist cannot be read (app not installed yet, or the
    /// container is unreadable): an advisory check must not invent findings.
    private func warnIfSilentPushCannotWake(payload: Data, udid: String, bundleID: String) {
        guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let aps = object["aps"] as? [String: Any] else { return }
        let contentAvailable = (aps["content-available"] as? NSNumber)?.intValue ?? 0
        guard contentAvailable == 1, aps["alert"] == nil else { return }
        guard let modes = SimShell.appBackgroundModes(udid: udid, bundleID: bundleID),
              !modes.contains("remote-notification") else { return }
        let declared: String = modes.isEmpty
            ? " (no background modes at all)"
            : " (has: \(modes.joined(separator: ", ")))"
        var message = "[sipi] warning: silent push (content-available, no alert) to \(bundleID), "
        message += "but its Info.plist declares no 'remote-notification' UIBackgroundModes"
        message += declared
        message += ". iOS will not wake the app, so this step cannot observe a reaction. "
        message += "Add the background mode to the app, or send an alert payload (aps.alert) "
        message += "if the test only needs a visible notification."
        emitError(message)
    }

    /// Resolve the `type` action's text-entry method, defaulting to paste so
    /// input is independent of the guest keyboard layout and input language.
    private func resolveInputMethod(_ raw: String?) throws -> TextInputMethod {
        guard let raw else { return .paste }
        guard let method = TextInputMethod(rawValue: raw) else {
            throw HarnessError("type input-method must be 'paste' or 'keyboard'.")
        }
        return method
    }

    /// Wait (bounded) for the accessibility tree to become usable, and return the
    /// last tree fetched.
    ///
    /// Right after `simctl launch` the bridge answers with a degenerate tree — a
    /// single 0x0 `Application` root, no children — until the app is actually
    /// reachable. On iOS 26 the fixed post-launch sleep covered it; on iOS 27.0 it
    /// does not, and the first step of every test failed as "element not found"
    /// against an empty tree. Polling here turns that into a short wait instead of
    /// a false failure. Returning the last tree (even if still degenerate) keeps
    /// the caller's own error path in charge of reporting.
    @discardableResult
    private func waitForUsableTree(timeout: TimeInterval = 5.0) -> [AXNode] {
        let deadline = Date().addingTimeInterval(timeout)
        var roots = (try? driver.describe(udid, deep: false)) ?? []
        while ChildTree.isDegenerate(roots), Date() < deadline {
            usleep(250 * 1000)
            roots = (try? driver.describe(udid, deep: false)) ?? []
        }
        return roots
    }

    private func resolvingRoots(query: AccessibilityQuery, elementType: String?) throws -> [AXNode] {
        var fast = try driver.describe(udid, deep: false)
        // An app that is still coming up yields a degenerate tree; resolving
        // against it would report the selector as missing. Wait for a real tree
        // first, then let resolution decide.
        if ChildTree.isDegenerate(fast) {
            fast = waitForUsableTree()
        }
        do {
            _ = try AccessibilityTargetResolver.resolveTap(roots: fast, query: query, elementType: elementType)
            return fast
        } catch let error as ElementResolutionError where error.isNotFound {
            let deep = try driver.describe(udid, deep: true)
            _ = try AccessibilityTargetResolver.resolveTap(roots: deep, query: query, elementType: elementType)
            return deep
        }
    }

    private func describeJSON(expect: String?) throws -> String {
        let fast = try driver.describe(udid, deep: false)
        let fastJSON = try AXNodeJSON.string(for: fast)
        if let expect, !expect.isEmpty, !fastJSON.contains(expect) {
            return try AXNodeJSON.string(for: driver.describe(udid, deep: true))
        }
        return fastJSON
    }

    private func normalizedPoint(_ point: HarnessPoint) throws -> Point {
        let unit = CoordinateUnit(rawValue: point.unit ?? "norm") ?? .norm
        let screen = unit == .pixel ? try screenSize() : nil
        return try CoordinateConverter.normalize(x: point.x, y: point.y, unit: unit, screen: screen)
    }

    private func screenSize() throws -> ScreenSize {
        let roots = try driver.describe(udid, deep: false)
        guard let frame = screenFrame(of: roots) else { throw HarnessError("Could not determine screen size.") }
        return ScreenSize(width: frame.width, height: frame.height)
    }

    private func accessibilityQuery(_ selector: HarnessSelector) throws -> AccessibilityQuery {
        let count = [selector.id != nil, selector.label != nil, selector.value != nil].filter { $0 }.count
        guard count == 1 else { throw HarnessError("selector requires exactly one of id, label, or value.") }
        if let id = selector.id { return .id(id) }
        if let label = selector.label { return .label(label) }
        return .value(selector.value!)
    }

    private func attemptedMethod(for selector: HarnessSelector) -> [String: Any] {
        if let id = selector.id { return ["method": "tap-id", "value": id] }
        if let label = selector.label { return ["method": "tap-label", "value": label] }
        return ["method": "tap-value", "value": selector.value ?? ""]
    }

    private func actionDescription(_ action: HarnessAction) -> String {
        switch action.type {
        case "tap":
            if let selector = action.selector {
                if let id = selector.id { return "tap id \(id)" }
                if let label = selector.label { return "tap label \(label)" }
                if let value = selector.value { return "tap value \(value)" }
            }
            if let point = action.point { return "tap \(point.x),\(point.y)" }
            return "tap"
        case "long-press":
            if let selector = action.selector {
                if let id = selector.id { return "long-press id \(id)" }
                if let label = selector.label { return "long-press label \(label)" }
                if let value = selector.value { return "long-press value \(value)" }
            }
            if let point = action.point { return "long-press \(point.x),\(point.y)" }
            return "long-press"
        case "double-tap":
            if let selector = action.selector {
                if let id = selector.id { return "double-tap id \(id)" }
                if let label = selector.label { return "double-tap label \(label)" }
                if let value = selector.value { return "double-tap value \(value)" }
            }
            if let point = action.point { return "double-tap \(point.x),\(point.y)" }
            return "double-tap"
        case "pinch":
            return "pinch \(action.direction ?? "")"
        case "multitouch":
            return "multitouch phase \(action.phase ?? 0)"
        case "display-state":
            return "display-state \(action.settings?.summary ?? "")"
        case "biometrics":
            return "biometrics \(action.operation ?? "")"
        case "type":
            return (action.clear ?? false) ? "type text (clear)" : "type text"
        case "set-text":
            if let selector = action.selector {
                if let id = selector.id { return "set-text id \(id)" }
                if let label = selector.label { return "set-text label \(label)" }
                if let value = selector.value { return "set-text value \(value)" }
            }
            if let point = action.point { return "set-text \(point.x),\(point.y)" }
            return "set-text"
        case "key":
            return "key \(action.usage ?? 0)"
        case "key-combo":
            return "key-combo \(action.modifiers?.map(String.init).joined(separator: "+") ?? "")+\(action.key ?? 0)"
        case "key-sequence":
            return "key-sequence \(action.keycodes?.count ?? 0) keys"
        case "button":
            return "button \(action.button ?? "")"
        case "swipe":
            return "swipe"
        case "drag":
            return "drag"
        case "gesture":
            return "gesture \(action.preset ?? "")"
        case "slider":
            if let selector = action.selector {
                let target = action.value.map { SliderPlan.formatPercent($0) } ?? "?"
                if let id = selector.id { return "slider id \(id) = \(target)" }
                if let label = selector.label { return "slider label \(label) = \(target)" }
            }
            return "slider"
        case "orientation":
            return "orientation \(action.orientation ?? "")"
        case "open-url":
            return "open-url \(action.url ?? "")"
        case "privacy":
            return "privacy \(action.operation ?? "") \(action.service ?? "")"
        case "push":
            return "push \(action.bundleID ?? bundleID)"
        case "location":
            return "location \(action.operation ?? "")"
        case "appearance":
            return "appearance \(action.appearance ?? "")"
        case "content-size":
            return "content-size \(action.contentSize ?? "")"
        case "increase-contrast":
            return "increase-contrast \(action.enabled.map { String($0) } ?? "")"
        case "status-bar":
            return "status-bar \(action.operation ?? "")"
        case "launch":
            return "launch \(action.bundleID ?? bundleID)"
        case "terminate":
            return "terminate \(action.bundleID ?? bundleID)"
        case "network-condition":
            return "network-condition \(action.operation ?? "") \(action.profile ?? "")"
        case "crown":
            return "crown \(action.delta ?? 0)"
        case "wait":
            return "wait"
        default:
            return action.type
        }
    }

    private func firstExpectedString(_ verify: HarnessVerify?) -> String? {
        guard let verify else { return nil }
        return (verify.contains ?? []).first ?? (verify.absent ?? []).first
    }

    private func writeResultJSON(
        test: HarnessTest,
        testDir: String,
        passed: Bool,
        review: Bool,
        steps: [[String: Any]],
        started: Date
    ) throws {
        let object: [String: Any] = [
            "id": test.id,
            "passed": passed,
            "review": review,
            "duration": Date().timeIntervalSince(started),
            "steps": steps
        ]
        try writeJSON(object.filterJSON(), to: testDir + "/result.json")
    }

    private func writeRunJSON(finished: Date?) throws {
        let passed = runEntries.filter { $0["passed"] as? Bool == true }.count
        let failed = runEntries.filter { $0["passed"] as? Bool == false }.count
        let review = runEntries.filter { $0["review"] as? Bool == true }.count
        var object: [String: Any] = [
            "started": HarnessTime.iso(started),
            "device": udid,
            "device-name": device?.name ?? "",
            "device-runtime": device?.runtime ?? "",
            "session": URL(fileURLWithPath: runDir).lastPathComponent,
            "tests": runEntries,
            "summary": [
                "total": runEntries.count,
                "passed": passed,
                "failed": failed,
                "review": review
            ]
        ]
        if let suite = options.suiteName { object["suite"] = suite }
        if let finished { object["finished"] = HarnessTime.iso(finished) }
        if let commit = Self.gitCommit() { object["commit"] = commit }
        try writeJSON(object.filterJSON(), to: runDir + "/run.json")
    }

    private func writeJSON(_ object: [String: Any], to path: String) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: path))
    }

    private func screenFrame(of roots: [AXNode]) -> AXNode.Frame? {
        roots.first { $0.type == "Application" }?.frame ?? roots.first?.frame
    }

    private func normalized(_ point: Point, in frame: AXNode.Frame) -> Point? {
        guard frame.width > 0, frame.height > 0 else { return nil }
        return Point(x: (point.x - frame.x) / frame.width, y: (point.y - frame.y) / frame.height)
    }

    private static func loadConfig(workspace: String) throws -> HarnessConfig {
        let path = workspace + "/config.json"
        guard FileManager.default.fileExists(atPath: path) else {
            return HarnessConfig(
                app: nil,
                stepDelay: nil,
                maxRetries: nil,
                networkConditionProvider: nil
            )
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode(HarnessConfig.self, from: data)
    }

    private static func loadTest(path: String) throws -> HarnessTest {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode(HarnessTest.self, from: data)
    }

    private static func resolveUDID(driver: NativeDriver, requested: String?) throws -> String {
        if let requested { return requested }
        if let booted = try driver.devices().first(where: { $0.booted }) {
            return booted.udid
        }
        throw HarnessError("No booted simulator found. Pass --device or boot a simulator.")
    }

    private static func defaultRunDir(workspace: String, device: Device?) -> String {
        let name = (device?.name ?? "simulator")
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
        let commit = gitCommit() ?? "nogit"
        return workspace + "/runs/" + HarnessTime.directoryStamp() + "_" + name + "_" + commit
    }

    private static func gitCommit() -> String? {
        func runGit(_ args: [String]) -> String? {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = args
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            try? process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard var commit = runGit(["rev-parse", "--short", "HEAD"]), !commit.isEmpty else { return nil }
        if runGit(["diff", "--quiet"]) == nil { commit += "-dirty" }
        return commit
    }
}

private extension Dictionary where Key == String, Value == Any {
    func filterJSON() -> [String: Any] {
        var out: [String: Any] = [:]
        for (key, value) in self {
            if value is NSNull { continue }
            if let dict = value as? [String: Any] {
                out[key] = dict.filterJSON()
            } else if let array = value as? [[String: Any]] {
                out[key] = array.map { $0.filterJSON() }
            } else {
                out[key] = value
            }
        }
        return out
    }
}

// MARK: - CLI

extension Sipi {
    struct RunTest: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "run-test",
            abstract: "Run one explicit SimPilot v2 test spec with the deterministic harness."
        )

        @Argument(help: "Path to a .simpilot/tests/<id>.json v2 test spec.")
        var testPath: String

        @Option(name: .long, help: "Path to the .simpilot workspace.")
        var workspace: String = ".simpilot"

        @Option(name: .long, help: "Simulator UDID. Defaults to the first booted simulator.")
        var device: String?

        @Option(name: .long, help: "Bundle ID. Defaults to config.json app.")
        var bundleID: String?

        @Option(name: .long, help: "Run output directory. Defaults under .simpilot/runs.")
        var runDir: String?

        @Option(name: .long, help: "Retry count for each failing step.")
        var retries: Int?

        @Flag(name: .customLong("no-launch"), help: "Do not terminate/launch the app before running.")
        var noLaunch = false

        func run() throws {
            do {
                // Validate the spec before touching the simulator.
                let tests = try HarnessRunner.preflight(testPaths: [testPath])
                let runner = try HarnessRunner(options: HarnessRunOptions(
                    workspace: workspace,
                    udid: device,
                    bundleID: bundleID,
                    runDir: runDir,
                    retries: retries,
                    launch: !noLaunch,
                    suiteName: nil,
                    stopOnFailure: false,
                    resetBetweenTests: true
                ))
                let path = try runner.run(tests: tests)
                print("Run results: \(URL(fileURLWithPath: path).path)")
            } catch {
                FileHandle.standardError.write(Data((String(describing: error) + "\n").utf8))
                throw ExitCode.failure
            }
        }
    }

    struct RunSuite: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "run-suite",
            abstract: "Run a SimPilot v2 suite with the deterministic harness."
        )

        @Argument(help: "Path to a .simpilot/suites/<name>.json suite.")
        var suitePath: String

        @Option(name: .long, help: "Path to the .simpilot workspace.")
        var workspace: String = ".simpilot"

        @Option(name: .long, help: "Simulator UDID. Defaults to the first booted simulator.")
        var device: String?

        @Option(name: .long, help: "Bundle ID. Defaults to config.json app.")
        var bundleID: String?

        @Option(name: .long, help: "Run output directory. Defaults under .simpilot/runs.")
        var runDir: String?

        @Option(name: .long, help: "Retry count for each failing step.")
        var retries: Int?

        @Flag(name: .customLong("no-launch"), help: "Do not terminate/launch the app before running.")
        var noLaunch = false

        func run() throws {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: suitePath))
                let suite = try JSONDecoder().decode(HarnessSuite.self, from: data)
                // A suite entry maps to tests/<id>.json; reject anything that is not
                // a safe single path component before building a path from it.
                for name in suite.tests where !PathSafety.isSafeComponent(name) {
                    throw HarnessError("suite test id '\(name)' is not a safe path component")
                }
                let paths = suite.tests.map { workspace + "/tests/" + $0 + ".json" }
                // Validate every spec before touching the simulator.
                let tests = try HarnessRunner.preflight(testPaths: paths)
                let runner = try HarnessRunner(options: HarnessRunOptions(
                    workspace: workspace,
                    udid: device,
                    bundleID: bundleID,
                    runDir: runDir,
                    retries: retries,
                    launch: !noLaunch,
                    suiteName: suite.name,
                    stopOnFailure: suite.settings?.stopOnFailure ?? false,
                    resetBetweenTests: suite.settings?.resetBetweenTests ?? true
                ))
                let path = try runner.run(tests: tests)
                print("Run results: \(URL(fileURLWithPath: path).path)")
            } catch {
                FileHandle.standardError.write(Data((String(describing: error) + "\n").utf8))
                throw ExitCode.failure
            }
        }
    }
}
