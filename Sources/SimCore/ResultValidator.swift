// ResultValidator.swift
//
// Schema validation for a `.simpilot` workspace (config / tests / suites /
// devices / runs / results). This is the in-binary home of what used to be the
// loose interpreter script validate_simpilot_results.swift under sipi-test;
// folding it into the sipi binary keeps the curl|bash install a single
// self-contained download. The skill docs now call `sipi validate <path>`.
//
// Validation logic is preserved from the original script: the same required /
// optional key sets, kebab-case id checks, ISO-8601 timezone checks, run.json ↔
// result.json cross-file consistency, and the summary count cross-checks. The
// only change is structural: errors/warnings are collected and returned to the
// caller instead of being written directly to stderr + exit(). Pure Foundation,
// unit-testable.

import Foundation

/// Validates a `.simpilot` workspace and returns the collected diagnostics.
public enum ResultValidator {

    /// Outcome of validating a workspace: collected errors and warnings.
    /// `isValid` is true only when there are no errors (warnings are advisory).
    public struct ValidationOutcome {
        public let errors: [String]
        public let warnings: [String]
        public var isValid: Bool { errors.isEmpty }
    }

    /// A simple message-only error surfaced to the CLI for setup failures.
    public struct ValidationError: Error, CustomStringConvertible {
        public let message: String
        public init(_ message: String) { self.message = message }
        public var description: String { message }
    }

    private typealias JSON = [String: Any]

    // MARK: - Schema Definitions

    private static let configRequired: Set<String> = ["app"]
    private static let configOptional: Set<String> = ["step-delay", "max-retries", "keep-runs", "record-video", "build"]
    private static let buildOptional: Set<String> = ["project", "scheme", "configuration"]

    private static let testRequired: Set<String> = ["id", "title", "steps"]
    private static let testOptional: Set<String> = ["app", "tags", "preconditions", "created", "updated"]
    private static let testStepOptional: Set<String> = ["action", "verify", "optional", "note", "target", "hints"]
    private static let testTargetOptional: Set<String> = ["role", "ids", "texts", "screen", "within"]
    private static let testHintRequired: Set<String> = ["method"]
    private static let testHintOptional: Set<String> = ["device-class", "device-name", "ios", "orientation", "value", "last-used", "note"]
    private static let testHintMethods: Set<String> = ["tap-id", "tap-label", "touch-coordinate"]

    private static let suiteRequired: Set<String> = ["name", "tests"]
    private static let suiteOptional: Set<String> = ["description", "settings"]
    private static let suiteSettingsOptional: Set<String> = ["stop-on-failure", "reset-between-tests"]

    private static let profileRequired: Set<String> = ["name", "devices"]
    private static let profileOptional: Set<String> = ["description"]
    private static let profileDeviceOptional: Set<String> = ["model", "runtime", "udid"]

    private static let runRequired: Set<String> = ["started", "device", "tests", "summary"]
    private static let runOptional: Set<String> = ["finished", "device-name", "device-runtime", "suite", "profile", "commit", "session", "build-error"]
    private static let runTestRequired: Set<String> = ["id", "passed", "duration"]
    private static let runTestOptional: Set<String> = ["review", "skipped"]
    private static let runSummaryRequired: Set<String> = ["total", "passed", "failed"]
    private static let runSummaryOptional: Set<String> = ["review"]

    private static let resultRequired: Set<String> = ["id", "passed", "duration", "steps"]
    private static let resultOptional: Set<String> = ["review", "skipped", "video"]
    private static let resultStepRequired: Set<String> = ["passed"]
    private static let resultStepOptional: Set<String> = [
        "action", "verify", "note", "review", "skipped", "duration",
        "screenshot", "screenshots", "failure-type", "describe-ui-snapshot", "attempted-methods"
    ]
    private static let resultFailureTypes: Set<String> = ["action", "verify", "timeout"]
    private static let attemptedMethodRequired: Set<String> = ["method"]
    private static let attemptedMethodOptional: Set<String> = ["value"]
    private static let attemptedMethodTypes: Set<String> = ["tap-label", "tap-id", "touch-coordinate", "input"]
    private static let screenshotsOptional: Set<String> = ["before", "after"]
    private static let verifyRequired: Set<String> = ["check", "found"]
    private static let verifyOptional: Set<String> = ["grep-match"]

    private static let kebabRegex = try! NSRegularExpression(pattern: "^[a-z0-9]+(-[a-z0-9]+)*$")

    /// Internal mutable accumulator carried through the validators.
    private final class Diagnostics {
        var errors: [String] = []
        var warnings: [String] = []
    }

    // MARK: - Helpers

    private static func loadJSON(_ path: String, _ diag: Diagnostics) -> JSON? {
        guard let data = FileManager.default.contents(atPath: path) else {
            diag.errors.append("\(path): cannot read file")
            return nil
        }
        do {
            guard let dict = try JSONSerialization.jsonObject(with: data) as? JSON else {
                diag.errors.append("\(path): root must be an object")
                return nil
            }
            return dict
        } catch {
            diag.errors.append("\(path): invalid JSON (\(error.localizedDescription))")
            return nil
        }
    }

    private static func checkKeys(_ path: String, _ data: JSON, required: Set<String>, optional: Set<String>, prefix: String = "", _ diag: Diagnostics) {
        let keys = Set(data.keys)
        let missing = required.subtracting(keys).sorted()
        let unknown = keys.subtracting(required).subtracting(optional).sorted()
        if !missing.isEmpty { diag.errors.append("\(path): \(prefix)missing keys \(missing)") }
        if !unknown.isEmpty { diag.errors.append("\(path): \(prefix)unknown keys \(unknown)") }
    }

    /// True iff `value` is a JSON boolean. JSONSerialization parses `true`/`false`
    /// to a CFBoolean and numbers to NSNumber, but Swift's `is Bool` also matches
    /// the NSNumbers 0 and 1 (toll-free bridging) — so a whole-number 0/1 would
    /// otherwise be mistaken for a boolean. Test the CFTypeID to tell them apart.
    private static func isJSONBoolean(_ value: Any) -> Bool {
        CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID()
    }

    private static func checkBool(_ path: String, _ data: JSON, _ field: String, prefix: String = "", _ diag: Diagnostics) {
        if let val = data[field], !isJSONBoolean(val) { diag.errors.append("\(path): \(prefix)\(field) must be bool") }
    }

    private static func checkNumber(_ path: String, _ data: JSON, _ field: String, prefix: String = "", _ diag: Diagnostics) {
        if let val = data[field], !(val is NSNumber) || isJSONBoolean(val) { diag.errors.append("\(path): \(prefix)\(field) must be number") }
    }

    private static let iso8601Regex = try! NSRegularExpression(
        pattern: "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(\\.\\d+)?(Z|[+-]\\d{2}:\\d{2})$"
    )

    private static func hasTZ(_ s: String) -> Bool {
        iso8601Regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    private static func checkTZ(_ path: String, _ data: JSON, _ field: String, _ diag: Diagnostics) {
        guard let raw = data[field] else { return }
        if let val = raw as? String, hasTZ(val) { return }
        diag.errors.append("\(path): \(field) must be an ISO 8601 timestamp with timezone offset")
    }

    private static func isKebab(_ s: String) -> Bool {
        kebabRegex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    // MARK: - Validators

    private static func validateConfig(_ path: String, _ diag: Diagnostics) {
        guard let data = loadJSON(path, diag) else { return }
        checkKeys(path, data, required: configRequired, optional: configOptional, diag)
        if let build = data["build"] {
            guard let b = build as? JSON else { diag.errors.append("\(path): build must be an object"); return }
            let unknown = Set(b.keys).subtracting(buildOptional).sorted()
            if !unknown.isEmpty { diag.errors.append("\(path): build unknown keys \(unknown)") }
        }
    }

    private static func validateTest(_ path: String, _ diag: Diagnostics) {
        guard let data = loadJSON(path, diag) else { return }
        checkKeys(path, data, required: testRequired, optional: testOptional, diag)

        if let id = data["id"] as? String {
            let expected = id + ".json"
            if URL(fileURLWithPath: path).lastPathComponent != expected {
                diag.errors.append("\(path): filename must match id (\(expected))")
            }
            if !isKebab(id) { diag.errors.append("\(path): id must be kebab-case (got '\(id)')") }
        }

        if let preconditions = data["preconditions"] {
            guard let arr = preconditions as? [Any] else { diag.errors.append("\(path): preconditions must be an array"); return }
            for (i, item) in arr.enumerated() {
                if item is String { continue }
                guard let obj = item as? JSON else { diag.errors.append("\(path): preconditions[\(i)] must be a string or object"); continue }
                let allowed: Set<String> = ["check", "description", "grep"]
                let unknown = Set(obj.keys).subtracting(allowed).sorted()
                if !unknown.isEmpty { diag.errors.append("\(path): preconditions[\(i)] unknown keys \(unknown)") }
                let hasCheck = (obj["check"] as? String).map { !$0.isEmpty } ?? false
                let hasDesc = (obj["description"] as? String).map { !$0.isEmpty } ?? false
                if !hasCheck && !hasDesc { diag.errors.append("\(path): preconditions[\(i)] requires check or description") }
            }
        }

        if let steps = data["steps"] {
            guard let arr = steps as? [Any] else { diag.errors.append("\(path): steps must be an array"); return }
            for (i, item) in arr.enumerated() {
                guard let step = item as? JSON else { diag.errors.append("\(path): steps[\(i)] must be an object"); continue }
                let unknown = Set(step.keys).subtracting(testStepOptional).sorted()
                if !unknown.isEmpty { diag.errors.append("\(path): steps[\(i)] unknown keys \(unknown)") }
                if step["action"] == nil && step["verify"] == nil {
                    diag.errors.append("\(path): steps[\(i)] requires action or verify")
                }
                if let target = step["target"] {
                    guard let t = target as? JSON else { diag.errors.append("\(path): steps[\(i)].target must be an object"); continue }
                    let unknownT = Set(t.keys).subtracting(testTargetOptional).sorted()
                    if !unknownT.isEmpty { diag.errors.append("\(path): steps[\(i)].target unknown keys \(unknownT)") }
                }
                if let hints = step["hints"] {
                    guard let arr2 = hints as? [Any] else { diag.errors.append("\(path): steps[\(i)].hints must be an array"); continue }
                    for (hi, hItem) in arr2.enumerated() {
                        guard let hint = hItem as? JSON else { diag.errors.append("\(path): steps[\(i)].hints[\(hi)] must be an object"); continue }
                        checkKeys(path, hint, required: testHintRequired, optional: testHintOptional, prefix: "steps[\(i)].hints[\(hi)] ", diag)
                        if let m = hint["method"] as? String, !testHintMethods.contains(m) {
                            diag.errors.append("\(path): steps[\(i)].hints[\(hi)].method must be one of \(testHintMethods.sorted())")
                        }
                    }
                }
            }
        }
    }

    private static func validateSuite(_ path: String, _ diag: Diagnostics) {
        guard let data = loadJSON(path, diag) else { return }
        checkKeys(path, data, required: suiteRequired, optional: suiteOptional, diag)
        if let name = data["name"] as? String {
            let expected = name + ".json"
            if URL(fileURLWithPath: path).lastPathComponent != expected {
                diag.errors.append("\(path): filename must match name (\(expected))")
            }
        }
        if let tests = data["tests"] {
            guard let arr = tests as? [Any] else { diag.errors.append("\(path): tests must be an array"); return }
            for (i, item) in arr.enumerated() {
                if !(item is String) { diag.errors.append("\(path): tests[\(i)] must be a string") }
            }
        }
        if let settings = data["settings"] {
            guard let s = settings as? JSON else { diag.errors.append("\(path): settings must be an object"); return }
            let unknown = Set(s.keys).subtracting(suiteSettingsOptional).sorted()
            if !unknown.isEmpty { diag.errors.append("\(path): settings unknown keys \(unknown)") }
        }
    }

    private static func validateProfile(_ path: String, _ diag: Diagnostics) {
        guard let data = loadJSON(path, diag) else { return }
        checkKeys(path, data, required: profileRequired, optional: profileOptional, diag)
        if let name = data["name"] as? String {
            let expected = name + ".json"
            if URL(fileURLWithPath: path).lastPathComponent != expected {
                diag.errors.append("\(path): filename must match name (\(expected))")
            }
        }
        guard let devices = data["devices"] as? [Any] else { diag.errors.append("\(path): devices must be an array"); return }
        for (i, item) in devices.enumerated() {
            guard let dev = item as? JSON else { diag.errors.append("\(path): devices[\(i)] must be an object"); continue }
            let unknown = Set(dev.keys).subtracting(profileDeviceOptional).sorted()
            if !unknown.isEmpty { diag.errors.append("\(path): devices[\(i)] unknown keys \(unknown)") }
            if dev["model"] == nil && dev["runtime"] == nil && dev["udid"] == nil {
                diag.errors.append("\(path): devices[\(i)] requires model, runtime, or udid")
            }
        }
    }

    @discardableResult
    private static func validateRun(_ path: String, _ diag: Diagnostics) -> JSON? {
        guard let data = loadJSON(path, diag) else { return nil }
        checkKeys(path, data, required: runRequired, optional: runOptional, diag)
        checkTZ(path, data, "started", diag)
        checkTZ(path, data, "finished", diag)

        var actualPassed = 0
        var actualFailed = 0
        var actualReview = 0
        var testEntries: [JSON] = []

        if let tests = data["tests"] {
            guard let arr = tests as? [Any] else { diag.errors.append("\(path): tests must be an array"); return nil }
            for (i, item) in arr.enumerated() {
                guard let test = item as? JSON else { diag.errors.append("\(path): tests[\(i)] must be an object"); continue }
                checkKeys(path, test, required: runTestRequired, optional: runTestOptional, prefix: "tests[\(i)] ", diag)
                checkBool(path, test, "passed", prefix: "tests[\(i)].", diag)
                checkNumber(path, test, "duration", prefix: "tests[\(i)].", diag)
                testEntries.append(test)
                if let p = test["passed"] as? Bool {
                    if p { actualPassed += 1 } else { actualFailed += 1 }
                }
                if test["review"] as? Bool == true { actualReview += 1 }
            }
        }

        if let summary = data["summary"] {
            guard let s = summary as? JSON else { diag.errors.append("\(path): summary must be an object"); return nil }
            checkKeys(path, s, required: runSummaryRequired, optional: runSummaryOptional, prefix: "summary ", diag)

            // Cross-check summary counts against actual test entries
            if let total = s["total"] as? Int, total != testEntries.count {
                diag.errors.append("\(path): summary.total is \(total) but tests array has \(testEntries.count) entries")
            }
            if let passed = s["passed"] as? Int, passed != actualPassed {
                diag.errors.append("\(path): summary.passed is \(passed) but \(actualPassed) tests actually passed")
            }
            if let failed = s["failed"] as? Int, failed != actualFailed {
                diag.errors.append("\(path): summary.failed is \(failed) but \(actualFailed) tests actually failed")
            }
            if let review = s["review"] as? Int {
                if review != actualReview {
                    diag.errors.append("\(path): summary.review is \(review) but \(actualReview) tests have review")
                }
            } else if actualReview > 0 {
                diag.errors.append("\(path): summary missing review field but \(actualReview) tests have review")
            }
        }
        return data
    }

    private static func validateResult(_ path: String, testStepCounts: [String: Int], _ diag: Diagnostics) {
        guard let data = loadJSON(path, diag) else { return }
        checkKeys(path, data, required: resultRequired, optional: resultOptional, diag)
        checkBool(path, data, "passed", diag)
        checkNumber(path, data, "duration", diag)

        guard let steps = data["steps"] as? [Any] else { diag.errors.append("\(path): steps must be an array"); return }

        for (i, item) in steps.enumerated() {
            guard let step = item as? JSON else { diag.errors.append("\(path): steps[\(i)] must be an object"); continue }
            let stepKeys = Set(step.keys)
            let missing = resultStepRequired.subtracting(stepKeys).sorted()
            let unknown = stepKeys.subtracting(resultStepRequired).subtracting(resultStepOptional).sorted()
            if !missing.isEmpty { diag.errors.append("\(path): steps[\(i)] missing keys \(missing)") }
            if !unknown.isEmpty { diag.errors.append("\(path): steps[\(i)] unknown keys \(unknown)") }
            checkBool(path, step, "passed", prefix: "steps[\(i)].", diag)
            checkNumber(path, step, "duration", prefix: "steps[\(i)].", diag)

            // verify array
            if let verify = step["verify"] {
                guard let arr = verify as? [Any] else { diag.errors.append("\(path): steps[\(i)].verify must be an array"); continue }
                for (vi, v) in arr.enumerated() {
                    guard let vObj = v as? JSON else { diag.errors.append("\(path): steps[\(i)].verify[\(vi)] must be an object"); continue }
                    checkKeys(path, vObj, required: verifyRequired, optional: verifyOptional, prefix: "steps[\(i)].verify[\(vi)] ", diag)
                }
            }

            // failure-type enum
            if let ft = step["failure-type"] as? String, !resultFailureTypes.contains(ft) {
                diag.errors.append("\(path): steps[\(i)].failure-type must be one of \(resultFailureTypes.sorted())")
            }

            // screenshots object
            if let ss = step["screenshots"] {
                guard let s = ss as? JSON else { diag.errors.append("\(path): steps[\(i)].screenshots must be an object"); continue }
                let unknown = Set(s.keys).subtracting(screenshotsOptional).sorted()
                if !unknown.isEmpty { diag.errors.append("\(path): steps[\(i)].screenshots unknown keys \(unknown)") }
            }

            // attempted-methods array
            if let am = step["attempted-methods"] {
                guard let arr = am as? [Any] else { diag.errors.append("\(path): steps[\(i)].attempted-methods must be an array"); continue }
                for (ai, a) in arr.enumerated() {
                    guard let aObj = a as? JSON else { diag.errors.append("\(path): steps[\(i)].attempted-methods[\(ai)] must be an object"); continue }
                    checkKeys(path, aObj, required: attemptedMethodRequired, optional: attemptedMethodOptional, prefix: "steps[\(i)].attempted-methods[\(ai)] ", diag)
                    if let m = aObj["method"] as? String, !attemptedMethodTypes.contains(m) {
                        diag.errors.append("\(path): steps[\(i)].attempted-methods[\(ai)].method must be one of \(attemptedMethodTypes.sorted())")
                    }
                }
            }
        }

        // Cross-check top-level passed against step outcomes
        if let topPassed = data["passed"] as? Bool {
            let topSkipped = data["skipped"] as? Bool ?? false
            if !topSkipped {
                let hasFailedStep = steps.contains { item in
                    guard let step = item as? JSON else { return false }
                    let stepPassed = step["passed"] as? Bool ?? false
                    let stepSkipped = step["skipped"] as? Bool ?? false
                    return !stepPassed && !stepSkipped
                }
                if topPassed && hasFailedStep {
                    diag.errors.append("\(path): passed is true but contains failed steps")
                }
                let hasNonSkippedStep = steps.contains { item in
                    guard let step = item as? JSON else { return false }
                    return step["skipped"] as? Bool != true
                }
                if !topPassed && !hasFailedStep && hasNonSkippedStep {
                    diag.errors.append("\(path): passed is false but no steps failed")
                }
            }
        }

        if let testId = data["id"] as? String, let expected = testStepCounts[testId] {
            if steps.count != expected {
                diag.errors.append("\(path): result has \(steps.count) steps but test definition has \(expected)")
            }
        }
    }

    private static func collectTestStepCounts(_ testsDir: String) -> [String: Int] {
        var counts: [String: Int] = [:]
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: testsDir) else { return counts }
        for item in items where item.hasSuffix(".json") {
            let path = testsDir + "/" + item
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let json = try? JSONSerialization.jsonObject(with: data) as? JSON,
                  let id = json["id"] as? String,
                  let steps = json["steps"] as? [Any] else { continue }
            counts[id] = steps.count
        }
        return counts
    }

    // MARK: - Entry point

    /// Validate the `.simpilot` workspace at `workspace`. Throws ValidationError
    /// if the workspace directory does not exist; otherwise returns the collected
    /// errors/warnings (an empty `errors` list means the workspace is valid).
    public static func validate(workspace: String) throws -> ValidationOutcome {
        let fm = FileManager.default

        guard fm.fileExists(atPath: workspace) else {
            throw ValidationError("\(workspace): directory does not exist")
        }

        let diag = Diagnostics()

        let configPath = workspace + "/config.json"
        if !fm.fileExists(atPath: configPath) {
            diag.errors.append("\(configPath): missing file")
        } else {
            validateConfig(configPath, diag)
        }

        let testsDir = workspace + "/tests"
        if fm.fileExists(atPath: testsDir) {
            let items = (try? fm.contentsOfDirectory(atPath: testsDir))?.sorted() ?? []
            for item in items where item.hasSuffix(".json") { validateTest(testsDir + "/" + item, diag) }
        }

        let suitesDir = workspace + "/suites"
        if fm.fileExists(atPath: suitesDir) {
            let items = (try? fm.contentsOfDirectory(atPath: suitesDir))?.sorted() ?? []
            for item in items where item.hasSuffix(".json") { validateSuite(suitesDir + "/" + item, diag) }
        }

        let devicesDir = workspace + "/devices"
        if fm.fileExists(atPath: devicesDir) {
            let items = (try? fm.contentsOfDirectory(atPath: devicesDir))?.sorted() ?? []
            for item in items where item.hasSuffix(".json") { validateProfile(devicesDir + "/" + item, diag) }
        }

        let testStepCounts = collectTestStepCounts(testsDir)
        let testIds = Set(testStepCounts.keys)

        let runsDir = workspace + "/runs"
        if fm.fileExists(atPath: runsDir) {
            let runDirs = ((try? fm.contentsOfDirectory(atPath: runsDir)) ?? []).sorted()
            for dir in runDirs {
                let runDirPath = runsDir + "/" + dir
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: runDirPath, isDirectory: &isDir), isDir.boolValue else { continue }
                let runJson = runDirPath + "/run.json"
                if !fm.fileExists(atPath: runJson) {
                    diag.errors.append("\(runJson): missing file")
                } else {
                    let runData = validateRun(runJson, diag)

                    // Cross-file consistency: run.json ↔ result.json
                    if let runData = runData, let runTests = runData["tests"] as? [JSON] {
                        let hasBuildError = runData["build-error"] != nil
                        for (i, entry) in runTests.enumerated() {
                            guard let tid = entry["id"] as? String else { continue }

                            // Check test definition exists
                            if !testIds.contains(tid) {
                                if testIds.isEmpty {
                                    diag.warnings.append("\(runJson): tests[\(i)] references '\(tid)' but no test definitions found in tests/")
                                } else {
                                    diag.errors.append("\(runJson): tests[\(i)] references unknown test id '\(tid)'")
                                }
                            }

                            // Check result.json exists for this test (suppress when build-error present)
                            let resultPath = runDirPath + "/" + tid + "/result.json"
                            if !fm.fileExists(atPath: resultPath) {
                                if !hasBuildError {
                                    diag.errors.append("\(resultPath): missing result.json for test '\(tid)' listed in run.json")
                                }
                            } else if let resultData = loadJSON(resultPath, diag) {
                                // Check passed consistency between run.json and result.json
                                if let runPassed = entry["passed"] as? Bool,
                                   let resPassed = resultData["passed"] as? Bool,
                                   runPassed != resPassed {
                                    diag.errors.append("\(runJson): tests[\(i)] passed=\(runPassed) but \(resultPath) passed=\(resPassed)")
                                }
                            }
                        }
                    }
                }
                let subdirs = ((try? fm.contentsOfDirectory(atPath: runDirPath)) ?? []).sorted()
                for sub in subdirs {
                    let resultPath = runDirPath + "/" + sub + "/result.json"
                    if fm.fileExists(atPath: resultPath) { validateResult(resultPath, testStepCounts: testStepCounts, diag) }
                }
            }
        }

        return ValidationOutcome(errors: diag.errors, warnings: diag.warnings)
    }
}
