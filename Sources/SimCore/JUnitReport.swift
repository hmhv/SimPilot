// JUnitReport.swift
//
// A JUnit XML rendering of a test run, for CI systems that ingest that format
// (GitHub Actions annotations, GitLab, Jenkins, Buildkite, Xcode Cloud's
// post-actions). It is derived from the same `run.json` / `result.json` the
// harness already writes — never a second source of truth — so it can be
// regenerated after the fact with `sipi report <run-dir> --junit`.
//
// Mapping:
//   <testsuite>  one per run, named after the suite (or the run id for a
//                single test), stamped with device, runtime, udid, commit
//   <testcase>   one per test; classname is the suite name so CI groups them
//   <failure>    the first failed step — type, action, unmet verify, note — and
//                the relative screenshot path, which is what a reader opens next
//   <skipped>    a test the harness skipped (stop-on-failure)
//   review       a passing test flagged for review keeps its pass and notes the
//                flag in <system-out>; CI has no third state

import Foundation

public enum JUnitReport {
    public struct JUnitError: Error, CustomStringConvertible {
        public let message: String
        public var description: String { message }
    }

    /// Render `<runDir>/run.json` (+ each test's result.json) as JUnit XML.
    public static func xml(runDir: String) throws -> String {
        guard let run = loadJSON(runDir + "/run.json") else {
            throw JUnitError(message: "\(runDir)/run.json: not found or invalid")
        }
        let runID = URL(fileURLWithPath: runDir).lastPathComponent
        let suiteName = (run["suite"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? runID
        let tests = run["tests"] as? [[String: Any]] ?? []

        var cases: [String] = []
        var failures = 0
        var skipped = 0
        var totalTime = 0.0
        for entry in tests {
            guard let id = entry["id"] as? String else { continue }
            let duration = number(entry["duration"])
            totalTime += duration
            var body: [String] = []
            let result = safeComponent(id) ? loadJSON(runDir + "/" + id + "/result.json") : nil

            if entry["skipped"] as? Bool == true {
                skipped += 1
                body.append("    <skipped/>")
            } else if entry["passed"] as? Bool == false {
                failures += 1
                let failure = describeFailure(testID: id, result: result)
                body.append(
                    "    <failure message=\"\(escape(failure.message))\" type=\"\(escape(failure.type))\">"
                    + escape(failure.detail) + "</failure>")
            } else if entry["review"] as? Bool == true {
                body.append("    <system-out>flagged for review</system-out>")
            }

            var testcase = "  <testcase name=\"\(escape(id))\" classname=\"\(escape(suiteName))\" time=\"\(format(duration))\""
            if body.isEmpty {
                testcase += "/>"
            } else {
                testcase += ">\n" + body.joined(separator: "\n") + "\n  </testcase>"
            }
            cases.append(testcase)
        }

        var properties: [(String, String)] = []
        properties.append(("run-id", runID))
        if let v = run["device-name"] as? String, !v.isEmpty { properties.append(("device", v)) }
        if let v = run["device-runtime"] as? String, !v.isEmpty { properties.append(("runtime", v)) }
        if let v = run["device"] as? String, !v.isEmpty { properties.append(("udid", v)) }
        if let v = run["commit"] as? String, !v.isEmpty { properties.append(("commit", v)) }

        var lines: [String] = []
        lines.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        var suite = "<testsuite name=\"\(escape(suiteName))\" tests=\"\(tests.count)\" failures=\"\(failures)\""
        suite += " errors=\"0\" skipped=\"\(skipped)\" time=\"\(format(totalTime))\""
        if let started = run["started"] as? String, !started.isEmpty {
            suite += " timestamp=\"\(escape(started))\""
        }
        if let host = run["device-name"] as? String, !host.isEmpty {
            suite += " hostname=\"\(escape(host))\""
        }
        suite += ">"
        lines.append(suite)
        lines.append("  <properties>")
        for (name, value) in properties {
            lines.append("    <property name=\"\(escape(name))\" value=\"\(escape(value))\"/>")
        }
        lines.append("  </properties>")
        lines.append(contentsOf: cases)
        lines.append("</testsuite>")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Write `<runDir>/junit.xml` and return its path.
    @discardableResult
    public static func write(runDir: String) throws -> String {
        let xml = try xml(runDir: runDir)
        let outPath = runDir + "/junit.xml"
        do {
            try xml.write(toFile: outPath, atomically: true, encoding: .utf8)
        } catch {
            throw JUnitError(message: "could not write \(outPath): \(error.localizedDescription)")
        }
        return outPath
    }

    // MARK: - Failure description

    struct Failure {
        var type: String
        var message: String
        var detail: String
    }

    /// The first failed step of a result, in one line for `message` and with the
    /// evidence pointers in the element body. A test that failed without a
    /// failing step (fixture restoration) is described from `cleanup-error`.
    static func describeFailure(testID: String, result: [String: Any]?) -> Failure {
        guard let result else {
            return Failure(type: "action", message: "result.json missing", detail: "\(testID)/result.json was not written")
        }
        let steps = result["steps"] as? [[String: Any]] ?? []
        if let index = steps.firstIndex(where: { $0["passed"] as? Bool == false }) {
            let step = steps[index]
            let type = step["failure-type"] as? String ?? "action"
            let action = step["action"] as? String ?? "(verify-only)"
            var message = "step \(index + 1) (\(action)): \(type)"
            var detail: [String] = []
            if let verify = step["verify"] as? [[String: Any]],
               let missing = verify.first(where: { $0["found"] as? Bool == false })?["check"] as? String {
                message += " — \(missing)"
                detail.append("unmet: \(missing)")
            }
            if let note = step["note"] as? String, !note.isEmpty {
                if !(step["verify"] is [[String: Any]]) || type == "action" { message += " — \(note)" }
                detail.append("note: \(note)")
            }
            if let screenshot = step["screenshot"] as? String {
                detail.append("screenshot: \(testID)/\(screenshot)")
            }
            return Failure(type: type, message: message, detail: detail.joined(separator: "\n"))
        }
        if let cleanup = result["cleanup-error"] as? String {
            return Failure(type: "cleanup", message: "fixture restoration failed", detail: cleanup)
        }
        return Failure(type: "action", message: "failed without a failing step", detail: "")
    }

    // MARK: - Helpers

    private static func loadJSON(_ path: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func safeComponent(_ id: String) -> Bool {
        !id.isEmpty && !id.contains("/") && !id.contains("..")
    }

    private static func number(_ value: Any?) -> Double {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        return 0
    }

    private static func format(_ seconds: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), seconds)
    }

    /// Escape for both attribute values and element text.
    static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.utf8.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            case "\n", "\t": out.unicodeScalars.append(scalar)
            case _ where scalar.value < 0x20: continue   // XML 1.0 forbids other control chars
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }
}
