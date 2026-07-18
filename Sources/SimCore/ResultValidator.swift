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
    private static let testOptional: Set<String> = ["app", "tags", "created", "updated"]
    private static let testStepOptional: Set<String> = ["id", "action", "verify", "optional", "wait", "note"]
    private static let testActionOptional: Set<String> = [
        "type", "selector", "point", "text", "usage", "button", "start", "end", "duration",
        "value", "tolerance", "preset", "modifiers", "key", "keycodes", "delay", "steps", "orientation", "delta"
    ]
    private static let testSelectorOptional: Set<String> = ["id", "label", "value", "element-type"]
    private static let testPointOptional: Set<String> = ["x", "y", "unit"]
    private static let testVerifyOptional: Set<String> = ["contains", "absent"]
    private static let testActionTypes: Set<String> = [
        "tap", "type", "key", "button", "swipe", "wait",
        "long-press", "slider", "gesture", "key-combo", "key-sequence", "drag", "orientation", "crown"
    ]

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
    private static let attemptedMethodTypes: Set<String> = ["tap-label", "tap-id", "tap-value", "touch-coordinate", "input"]
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

    private static func checkString(_ path: String, _ data: JSON, _ field: String, prefix: String = "", _ diag: Diagnostics) {
        if let val = data[field], !(val is String) { diag.errors.append("\(path): \(prefix)\(field) must be a string") }
    }

    private static func checkStringArray(_ path: String, _ data: JSON, _ field: String, prefix: String = "", _ diag: Diagnostics) {
        guard let val = data[field] else { return }
        guard let arr = val as? [Any], arr.allSatisfy({ $0 is String }) else {
            diag.errors.append("\(path): \(prefix)\(field) must be an array of strings")
            return
        }
    }

    /// A JSON number that is a whole value AND representable as `Int` — so a spec
    /// that validates decodes into the harness's `Int` fields. `1e20` is integral
    /// as a Double but overflows `Int`, so `Int(exactly:)` (not `.rounded()`)
    /// is the correct test.
    private static func isJSONInteger(_ value: Any) -> Bool {
        guard let n = value as? NSNumber, !isJSONBoolean(value) else { return false }
        return Int(exactly: n.doubleValue) != nil
    }

    /// Upper bound for a time field, in seconds. Beyond this the harness's
    /// `UInt32(seconds * 1_000_000)` sleep conversion would overflow; the value
    /// is also far larger than any reasonable UI wait.
    private static let maxDurationSeconds = 600.0

    private static func checkSecondsRange(_ path: String, _ data: JSON, _ field: String, prefix: String = "", _ diag: Diagnostics) {
        guard let v = numberValue(data[field]) else { return }  // non-number handled by checkNumber
        if !(v >= 0 && v <= maxDurationSeconds) {
            diag.errors.append("\(path): \(prefix)\(field) must be between 0 and \(Int(maxDurationSeconds)) seconds")
        }
    }

    private static func checkInteger(_ path: String, _ data: JSON, _ field: String, prefix: String = "", _ diag: Diagnostics) {
        if let val = data[field], !isJSONInteger(val) { diag.errors.append("\(path): \(prefix)\(field) must be an integer") }
    }

    private static func checkIntegerArray(_ path: String, _ data: JSON, _ field: String, prefix: String = "", _ diag: Diagnostics) {
        guard let val = data[field] else { return }
        guard let arr = val as? [Any], arr.allSatisfy({ isJSONInteger($0) }) else {
            diag.errors.append("\(path): \(prefix)\(field) must be an array of integers")
            return
        }
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
        checkString(path, data, "app", diag)
        checkNumber(path, data, "step-delay", diag)
        checkInteger(path, data, "max-retries", diag)
        checkInteger(path, data, "keep-runs", diag)
        checkBool(path, data, "record-video", diag)
        // Practical bounds: a huge max-retries would loop ~forever and a huge
        // step-delay would stall each retry for over an hour. (The runner also
        // clamps these, since run-test does not validate config.)
        if let r = numberValue(data["max-retries"]), !(r >= 0 && r <= 10) {
            diag.errors.append("\(path): max-retries must be between 0 and 10")
        }
        if let d = numberValue(data["step-delay"]), !(d >= 0 && d <= 60) {
            diag.errors.append("\(path): step-delay must be between 0 and 60 seconds")
        }
        if let build = data["build"] {
            guard let b = build as? JSON else { diag.errors.append("\(path): build must be an object"); return }
            let unknown = Set(b.keys).subtracting(buildOptional).sorted()
            if !unknown.isEmpty { diag.errors.append("\(path): build unknown keys \(unknown)") }
            for field in buildOptional { checkString(path, b, field, prefix: "build.", diag) }
        }
    }

    private static func validateTest(_ path: String, _ diag: Diagnostics) {
        guard let data = loadJSON(path, diag) else { return }
        checkKeys(path, data, required: testRequired, optional: testOptional, diag)
        checkString(path, data, "id", diag)
        checkString(path, data, "title", diag)
        checkString(path, data, "app", diag)
        checkStringArray(path, data, "tags", diag)

        if let id = data["id"] as? String {
            let expected = id + ".json"
            if URL(fileURLWithPath: path).lastPathComponent != expected {
                diag.errors.append("\(path): filename must match id (\(expected))")
            }
            if !isKebab(id) { diag.errors.append("\(path): id must be kebab-case (got '\(id)')") }
        }

        if let steps = data["steps"] {
            guard let arr = steps as? [Any] else { diag.errors.append("\(path): steps must be an array"); return }
            // A test with no steps runs nothing and would PASS vacuously.
            if arr.isEmpty { diag.errors.append("\(path): steps must have at least one step") }
            for (i, item) in arr.enumerated() {
                guard let step = item as? JSON else { diag.errors.append("\(path): steps[\(i)] must be an object"); continue }
                let unknown = Set(step.keys).subtracting(testStepOptional).sorted()
                if !unknown.isEmpty { diag.errors.append("\(path): steps[\(i)] unknown keys \(unknown)") }
                if step["action"] == nil && step["verify"] == nil {
                    diag.errors.append("\(path): steps[\(i)] requires action or verify")
                }
                checkString(path, step, "id", prefix: "steps[\(i)].", diag)
                checkString(path, step, "note", prefix: "steps[\(i)].", diag)
                checkBool(path, step, "optional", prefix: "steps[\(i)].", diag)
                checkNumber(path, step, "wait", prefix: "steps[\(i)].", diag)
                checkSecondsRange(path, step, "wait", prefix: "steps[\(i)].", diag)
                if let action = step["action"] {
                    guard let a = action as? JSON else { diag.errors.append("\(path): steps[\(i)].action must be an object"); continue }
                    validateAction(path, a, ordinal: "steps[\(i)].action", diag)
                }
                if let verify = step["verify"] {
                    guard let v = verify as? JSON else { diag.errors.append("\(path): steps[\(i)].verify must be an object"); continue }
                    let unknownV = Set(v.keys).subtracting(testVerifyOptional).sorted()
                    if !unknownV.isEmpty { diag.errors.append("\(path): steps[\(i)].verify unknown keys \(unknownV)") }
                    for key in ["contains", "absent"] where v[key] != nil {
                        guard let arr = v[key] as? [Any], arr.allSatisfy({ $0 is String }) else {
                            diag.errors.append("\(path): steps[\(i)].verify.\(key) must be a string array")
                            continue
                        }
                        // An empty/whitespace condition matches vacuously
                        // (`contains("")` is always true), so it would PASS without
                        // checking anything. Reject it.
                        for text in arr.compactMap({ $0 as? String }) where text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            diag.errors.append("\(path): steps[\(i)].verify.\(key) conditions must not be empty or whitespace")
                        }
                    }
                    // A verify with no conditions would pass vacuously in the harness
                    // (empty allSatisfy is true), so a verify-only step would PASS
                    // without checking anything. Require at least one condition.
                    let containsArr = (v["contains"] as? [Any]) ?? []
                    let absentArr = (v["absent"] as? [Any]) ?? []
                    if containsArr.isEmpty && absentArr.isEmpty {
                        diag.errors.append("\(path): steps[\(i)].verify must have at least one contains or absent condition")
                    }
                }
            }
        }
    }

    /// Validate a single action object: known keys, a known `type`, the
    /// structural shape of `selector`/points, and — the part that keeps `sipi
    /// validate` from green-lighting specs the harness will reject at runtime —
    /// the per-type required fields, exclusivity, and value ranges.
    /// `ordinal` is the dotted path prefix, e.g. `steps[0].action`.
    private static func validateAction(_ path: String, _ a: JSON, ordinal: String, _ diag: Diagnostics) {
        checkKeys(path, a, required: ["type"], optional: testActionOptional, prefix: ordinal + " ", diag)

        // Scalar field types must match the decoder, so a spec that validates
        // always decodes (no `sipi validate` OK → JSONDecoder failure gap).
        checkString(path, a, "text", prefix: ordinal + ".", diag)
        checkString(path, a, "button", prefix: ordinal + ".", diag)
        checkString(path, a, "preset", prefix: ordinal + ".", diag)
        checkString(path, a, "orientation", prefix: ordinal + ".", diag)
        for numField in ["duration", "delay", "value", "tolerance", "delta"] {
            checkNumber(path, a, numField, prefix: ordinal + ".", diag)
        }
        for intField in ["usage", "key", "steps"] {
            checkInteger(path, a, intField, prefix: ordinal + ".", diag)
        }
        for intArray in ["modifiers", "keycodes"] {
            checkIntegerArray(path, a, intArray, prefix: ordinal + ".", diag)
        }
        // Time fields feed a UInt32 microsecond sleep in the harness; bound them.
        checkSecondsRange(path, a, "duration", prefix: ordinal + ".", diag)
        checkSecondsRange(path, a, "delay", prefix: ordinal + ".", diag)

        guard let type = a["type"] as? String else {
            if a["type"] != nil { diag.errors.append("\(path): \(ordinal).type must be a string") }
            return
        }
        if !testActionTypes.contains(type) {
            diag.errors.append("\(path): \(ordinal).type must be one of \(testActionTypes.sorted())")
            return
        }

        // Selector shape (shared): known keys, string fields, exactly one of id/label/value.
        if let selector = a["selector"] {
            guard let s = selector as? JSON else { diag.errors.append("\(path): \(ordinal).selector must be an object"); return }
            let unknownS = Set(s.keys).subtracting(testSelectorOptional).sorted()
            if !unknownS.isEmpty { diag.errors.append("\(path): \(ordinal).selector unknown keys \(unknownS)") }
            for field in ["id", "label", "value", "element-type"] {
                checkString(path, s, field, prefix: "\(ordinal).selector.", diag)
            }
            let chosen = [s["id"], s["label"], s["value"]].filter { $0 != nil }.count
            if chosen != 1 { diag.errors.append("\(path): \(ordinal).selector requires exactly one of id, label, or value") }
        }
        // Point shape (shared): known keys, numeric x/y, valid unit.
        for pointKey in ["point", "start", "end"] where a[pointKey] != nil {
            validatePoint(path, a[pointKey]!, ordinal: "\(ordinal).\(pointKey)", diag)
        }

        switch type {
        case "tap", "long-press":
            if (a["selector"] != nil) == (a["point"] != nil) {
                diag.errors.append("\(path): \(ordinal) (\(type)) requires exactly one of selector or point")
            }
        case "type":
            if !(a["text"] is String) { diag.errors.append("\(path): \(ordinal) (type) requires a text string") }
        case "key":
            requireKeycode(path, a, "usage", ordinal: ordinal, diag)
        case "key-combo":
            requireKeycodeArray(path, a, "modifiers", ordinal: ordinal, diag)
            requireKeycode(path, a, "key", ordinal: ordinal, diag)
        case "key-sequence":
            requireKeycodeArray(path, a, "keycodes", ordinal: ordinal, diag)
        case "button":
            if let name = a["button"] as? String {
                if HardwareButton(rawValue: name) == nil {
                    diag.errors.append("\(path): \(ordinal).button must be one of \(HardwareButton.allCases.map(\.rawValue).sorted())")
                }
            } else {
                diag.errors.append("\(path): \(ordinal) (button) requires a button name")
            }
        case "swipe", "drag":
            if a["start"] == nil || a["end"] == nil {
                diag.errors.append("\(path): \(ordinal) (\(type)) requires start and end points")
            }
        case "gesture":
            if let preset = a["preset"] as? String {
                if GesturePreset(rawValue: preset) == nil {
                    diag.errors.append("\(path): \(ordinal).preset must be one of \(GesturePreset.allCases.map(\.rawValue).sorted())")
                }
            } else {
                diag.errors.append("\(path): \(ordinal) (gesture) requires a preset")
            }
        case "slider":
            if let s = a["selector"] as? JSON {
                if !(s["id"] is String) && !(s["label"] is String) {
                    diag.errors.append("\(path): \(ordinal).selector (slider) must use id or label")
                }
            } else {
                diag.errors.append("\(path): \(ordinal) (slider) requires a selector")
            }
            if let value = numberValue(a["value"]) {
                if !(value >= 0 && value <= 100) { diag.errors.append("\(path): \(ordinal).value must be between 0 and 100") }
            } else {
                diag.errors.append("\(path): \(ordinal) (slider) requires a numeric value (0...100)")
            }
            if let tolRaw = a["tolerance"] {
                if let tol = numberValue(tolRaw) {
                    if !(tol > 0 && tol <= 1) { diag.errors.append("\(path): \(ordinal).tolerance must be greater than 0 and at most 1") }
                } else {
                    diag.errors.append("\(path): \(ordinal).tolerance must be a number")
                }
            }
        case "orientation":
            if let name = a["orientation"] as? String {
                if OrientationSetName(name) == nil {
                    diag.errors.append("\(path): \(ordinal).orientation must be one of \(OrientationSetName.acceptedNames)")
                }
            } else {
                diag.errors.append("\(path): \(ordinal) (orientation) requires an orientation name")
            }
        case "crown":
            if numberValue(a["delta"]) == nil { diag.errors.append("\(path): \(ordinal) (crown) requires a numeric delta") }
        case "wait":
            if a["duration"] != nil, numberValue(a["duration"]) == nil {
                diag.errors.append("\(path): \(ordinal).duration must be a number")
            }
        default:
            break
        }
    }

    private static func validatePoint(_ path: String, _ raw: Any, ordinal: String, _ diag: Diagnostics) {
        guard let p = raw as? JSON else { diag.errors.append("\(path): \(ordinal) must be an object"); return }
        let unknown = Set(p.keys).subtracting(testPointOptional).sorted()
        if !unknown.isEmpty { diag.errors.append("\(path): \(ordinal) unknown keys \(unknown)") }
        let x = numberValue(p["x"])
        let y = numberValue(p["y"])
        if x == nil || y == nil {
            diag.errors.append("\(path): \(ordinal) requires numeric x and y")
        }
        var unit = "norm"  // CoordinateConverter default
        if let rawUnit = p["unit"] {
            if let u = rawUnit as? String {
                if u != "norm" && u != "pixel" { diag.errors.append("\(path): \(ordinal).unit must be norm or pixel") }
                else { unit = u }
            } else {
                diag.errors.append("\(path): \(ordinal).unit must be a string")
            }
        }
        // Mirror CoordinateConverter.normalize: norm coordinates must be 0...1;
        // pixel coordinates must be non-negative (upper bound needs the live
        // screen size, so it stays a runtime check).
        for (axis, value) in [("x", x), ("y", y)] {
            guard let value else { continue }
            if unit == "norm" {
                if !(value >= 0 && value <= 1) {
                    diag.errors.append("\(path): \(ordinal).\(axis) must be within 0...1 for norm coordinates")
                }
            } else if value < 0 {
                diag.errors.append("\(path): \(ordinal).\(axis) must be non-negative for pixel coordinates")
            }
        }
    }

    /// Return a JSON number as a Double, rejecting booleans (which bridge to NSNumber).
    private static func numberValue(_ value: Any?) -> Double? {
        guard let value, value is NSNumber, !isJSONBoolean(value) else { return nil }
        return (value as! NSNumber).doubleValue
    }

    private static func requireKeycode(_ path: String, _ a: JSON, _ field: String, ordinal: String, _ diag: Diagnostics) {
        guard let d = numberValue(a[field]), d >= 0, d <= 255, d == d.rounded() else {
            diag.errors.append("\(path): \(ordinal).\(field) must be an integer keycode (0...255)")
            return
        }
    }

    private static func requireKeycodeArray(_ path: String, _ a: JSON, _ field: String, ordinal: String, _ diag: Diagnostics) {
        guard let arr = a[field] as? [Any], !arr.isEmpty else {
            diag.errors.append("\(path): \(ordinal).\(field) must be a non-empty array of keycodes (0...255)")
            return
        }
        for item in arr {
            guard let d = numberValue(item), d >= 0, d <= 255, d == d.rounded() else {
                diag.errors.append("\(path): \(ordinal).\(field) must be a non-empty array of keycodes (0...255)")
                return
            }
        }
    }

    private static func validateSuite(_ path: String, _ diag: Diagnostics) {
        guard let data = loadJSON(path, diag) else { return }
        checkKeys(path, data, required: suiteRequired, optional: suiteOptional, diag)
        checkString(path, data, "name", diag)
        checkString(path, data, "description", diag)
        if let name = data["name"] as? String {
            let expected = name + ".json"
            if URL(fileURLWithPath: path).lastPathComponent != expected {
                diag.errors.append("\(path): filename must match name (\(expected))")
            }
        }
        if let tests = data["tests"] {
            guard let arr = tests as? [Any] else { diag.errors.append("\(path): tests must be an array"); return }
            for (i, item) in arr.enumerated() {
                // A suite entry is a test id that maps to tests/<id>.json; require
                // kebab-case so it cannot traverse out of the workspace ("../..").
                guard let name = item as? String else { diag.errors.append("\(path): tests[\(i)] must be a string"); continue }
                if !isKebab(name) { diag.errors.append("\(path): tests[\(i)] must be a kebab-case test id (got '\(name)')") }
            }
        }
        if let settings = data["settings"] {
            guard let s = settings as? JSON else { diag.errors.append("\(path): settings must be an object"); return }
            let unknown = Set(s.keys).subtracting(suiteSettingsOptional).sorted()
            if !unknown.isEmpty { diag.errors.append("\(path): settings unknown keys \(unknown)") }
            checkBool(path, s, "stop-on-failure", prefix: "settings.", diag)
            checkBool(path, s, "reset-between-tests", prefix: "settings.", diag)
        }
    }

    private static func validateProfile(_ path: String, _ diag: Diagnostics) {
        guard let data = loadJSON(path, diag) else { return }
        checkKeys(path, data, required: profileRequired, optional: profileOptional, diag)
        checkString(path, data, "name", diag)
        checkString(path, data, "description", diag)
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
            for field in profileDeviceOptional { checkString(path, dev, field, prefix: "devices[\(i)].", diag) }
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
    /// Validate a single v2 test spec file, the way `sipi run-test` /
    /// `sipi run-suite` gate a spec before running it. Reuses the same rules as
    /// the workspace-level test validation (schema, kebab-case id, per-action
    /// required fields and ranges), so a spec that runs is a spec that validates.
    public static func validateTestFile(_ path: String) -> ValidationOutcome {
        let diag = Diagnostics()
        validateTest(path, diag)
        return ValidationOutcome(errors: diag.errors, warnings: diag.warnings)
    }

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
