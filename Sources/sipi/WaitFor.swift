// WaitFor.swift
//
// `sipi wait-for` — poll the accessibility tree until a condition holds or a
// deadline passes. The saved-test harness has always had this (a step's verify
// is re-polled until `wait` seconds elapse); ad-hoc driving and the verify skill
// did not, so they slept a guessed number of seconds and re-read. A conditional
// wait finishes the moment the screen is ready and fails loudly when it never
// is, which is both faster and more honest than `sleep 3`.
//
// The condition vocabulary is the verify vocabulary, evaluated by the same
// `VerifyEvaluator` the harness uses — so absence is judged against the deep
// tree, presence escalates to it only on a miss, and "found" means exactly what
// a saved test's `verify` would have meant.

import ArgumentParser
import Foundation
import SimCore
import SimNative

extension Sipi {
    struct WaitFor: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "wait-for",
            abstract: "Poll the accessibility tree until an element or text appears (or, with --absent, disappears), then exit 0; exit 1 at the deadline.",
            discussion: """
            One condition per call: --label, --id, or --value select an element (exact
            match, both sides trimmed of surrounding whitespace, optionally narrowed
            with --element-type), --text is a verbatim substring search over the
            serialized tree — the same test a `contains` verify runs. --absent inverts
            it and is judged against the deep tree, like an `absent` verify.

            Prints one JSON object: satisfied, elapsed seconds, and the number of polls.
            The condition is checked once more when the deadline passes, so a call can
            run one poll longer than --timeout.
            """
        )

        @Argument(help: "Simulator UDID.")
        var udid: String

        @Option(name: .long, help: "Wait for an element whose AXLabel equals this.")
        var label: String?

        @Option(name: .long, help: "Wait for an element whose AXUniqueId equals this.")
        var id: String?

        @Option(name: .long, help: "Wait for an element whose AXValue equals this.")
        var value: String?

        @Option(name: .long, help: "Wait for this substring anywhere in the serialized tree (labels, values, ids).")
        var text: String?

        @Option(name: .customLong("element-type"), help: "Restrict --label/--id/--value matches to this accessibility type (e.g. Button).")
        var elementType: String?

        @Flag(name: .long, help: "Wait until the condition is NOT met (the element or text is gone).")
        var absent = false

        @Option(name: .long, help: "Seconds to keep polling before failing.")
        var timeout: Double = 10

        @Option(name: .long, help: "Seconds between polls.")
        var interval: Double = 0.5

        func validate() throws {
            if let problem = Self.selectionProblem(label: label, id: id, value: value, text: text, elementType: elementType) {
                throw ValidationError(problem)
            }
            guard timeout >= 0, timeout <= 600 else {
                throw ValidationError("--timeout must be between 0 and 600 seconds")
            }
            guard interval > 0, interval <= 60 else {
                throw ValidationError("--interval must be between 0 (exclusive) and 60 seconds")
            }
        }

        /// Why this combination of selector options cannot be waited on, or nil
        /// when it can. Exactly one selector, and never an empty one: an empty
        /// `--text` would be found in every tree (`contains("")` is always true)
        /// and report a screen it never tested, which is the same vacuous pass
        /// `sipi validate` rejects in a saved verify.
        static func selectionProblem(
            label: String?, id: String?, value: String?, text: String?, elementType: String?
        ) -> String? {
            let chosen = [label, id, value, text].compactMap { $0 }
            guard chosen.count == 1, let selector = chosen.first else {
                return "wait-for takes exactly one of --label, --id, --value, or --text"
            }
            if selector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "the wait-for selector must not be empty or whitespace: it would match every screen"
            }
            if elementType != nil, text != nil {
                return "--element-type narrows an element selector; it has no meaning with --text"
            }
            return nil
        }

        func run() throws {
            let condition = WaitCondition.from(
                label: label, id: id, value: value, text: text,
                elementType: elementType, absent: absent)
            let started = Date()
            let deadline = started.addingTimeInterval(timeout)
            var polls = 0
            var lastReason: String?

            while true {
                polls += 1
                do {
                    let fast = try ChildTree.nodes(udid: udid, deep: false)
                    let rows = try condition.evaluate(
                        fast: VerifyEvaluator.Capture(json: try AXNodeJSON.string(for: fast), nodes: fast),
                        deep: {
                            let deep = try ChildTree.nodes(udid: udid, deep: true)
                            return VerifyEvaluator.Capture(json: try AXNodeJSON.string(for: deep), nodes: deep)
                        })
                    if rows.allSatisfy(\.found) {
                        try emit(satisfied: true, condition: condition, started: started, polls: polls, reason: nil)
                        return
                    }
                    lastReason = rows.first { !$0.found }.map { row in
                        row.grepMatch.map { "\(row.check) — \($0)" } ?? row.check
                    }
                } catch {
                    // A tree that cannot be read yet (no frontmost app right after a
                    // boot, a launch race) is "not satisfied", not a failure of the
                    // wait itself; keep polling until the deadline.
                    lastReason = "tree unreadable: \(error)"
                }
                if Date() >= deadline { break }
                Thread.sleep(forTimeInterval: min(interval, max(0, deadline.timeIntervalSinceNow)))
            }

            try emit(satisfied: false, condition: condition, started: started, polls: polls, reason: lastReason)
            emitError("[sipi] wait-for: \(condition.description) not satisfied within \(formatSeconds(timeout))s"
                + (lastReason.map { " (\($0))" } ?? ""))
            throw ExitCode.failure
        }

        private func emit(satisfied: Bool, condition: WaitCondition, started: Date, polls: Int, reason: String?) throws {
            var object: [String: Any] = [
                "satisfied": satisfied,
                "condition": condition.description,
                // Three decimals, rendered from a decimal string so JSON shows 5.568
                // and not the binary-double noise a rounded Double prints as.
                "elapsed": NSDecimalNumber(string: String(format: "%.3f", Date().timeIntervalSince(started))),
                "polls": polls
            ]
            if let reason { object["reason"] = reason }
            let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }

        private func formatSeconds(_ seconds: Double) -> String {
            seconds == seconds.rounded() ? String(Int(seconds)) : String(seconds)
        }
    }
}

/// The one condition a `wait-for` call polls, expressed in verify terms so the
/// evaluation is shared with the harness.
struct WaitCondition {
    var label: String?
    var id: String?
    var value: String?
    var text: String?
    var elementType: String?
    var absent: Bool

    /// Build from CLI options. Element selectors are trimmed because that is how
    /// `ElementCondition` reads the tree — a `--label ' Sign In '` that kept its
    /// spaces would match nothing and, with `--absent`, report success over an
    /// element that is plainly there. `--text` is a substring and stays verbatim.
    static func from(
        label: String?, id: String?, value: String?, text: String?,
        elementType: String?, absent: Bool
    ) -> WaitCondition {
        func trimmed(_ s: String?) -> String? {
            s?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return WaitCondition(
            label: trimmed(label), id: trimmed(id), value: trimmed(value), text: text,
            elementType: trimmed(elementType), absent: absent)
    }

    /// The verify rows this condition produces against a capture.
    func evaluate(
        fast: VerifyEvaluator.Capture,
        deep: () throws -> VerifyEvaluator.Capture
    ) throws -> [VerifyEvaluator.Row] {
        if let text {
            return try VerifyEvaluator.evaluate(
                contains: absent ? [] : [text],
                absent: absent ? [text] : [],
                fast: fast, deep: deep)
        }
        let element = ElementCondition(
            id: id, label: label, value: value, elementType: elementType,
            exists: absent ? false : nil)
        return try VerifyEvaluator.evaluate(elements: [element], fast: fast, deep: deep)
    }

    var description: String {
        if let text { return (absent ? "absent: " : "contains: ") + text }
        var parts: [String] = []
        if let id { parts.append("id=\(id)") }
        if let label { parts.append("label=\(label)") }
        if let value { parts.append("value=\(value)") }
        if let elementType { parts.append("type=\(elementType)") }
        return "element: " + parts.joined(separator: " ") + (absent ? " [absent]" : " [exists]")
    }
}
