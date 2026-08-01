// A11yAudit.swift
//
// `sipi a11y-audit <udid>` — run the mechanical accessibility rules in
// SimCore.AccessibilityAudit against the live accessibility tree.
//
// Xcode's own equivalent, `XCUIApplication.performAccessibilityAudit`, only runs
// from inside a UI test target; there is no simctl or devicectl subcommand that
// audits a running app. This does it from the command line against any booted
// simulator, with no test target and no changes to the app under test.

import ArgumentParser
import Foundation
import SimCore
import SimNative

extension Sipi {
    struct A11yAudit: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "a11y-audit",
            abstract: "Audit the current screen for accessibility defects (touch targets, labels, truncation).",
            discussion: """
            Rules: \(A11yRule.allCases.map(\.rawValue).joined(separator: ", ")).

            Runs the deep (grid) accessibility pass by default so System UI and
            map/overlay elements the frontmost child tree cannot reach are audited too.
            Pass --fast to skip the grid pass when only the app's own controls matter.

            Contrast ratios and clipped text are out of scope: both need pixel analysis
            of the rendered frame, and guessing them from the accessibility tree would
            produce false positives. The `truncated-text` rule catches the clipping the
            guest itself reports with an ellipsis.

            Exits non-zero when a finding at or above --fail-on is present, so this can
            gate CI directly.
            """
        )

        @Argument(help: "Simulator UDID.")
        var udid: String

        @Flag(name: .long, help: "Emit findings as JSON.")
        var json = false

        @Flag(name: .long, help: "Skip the deep grid pass; audit only the frontmost app's child tree.")
        var fast = false

        @Option(
            name: .customLong("min-touch-target"),
            help: "Minimum touch target edge in points (default \(Int(AccessibilityAudit.minimumTouchTarget)))."
        )
        var minTouchTarget: Double = AccessibilityAudit.minimumTouchTarget

        @Option(
            name: .long,
            help: "Comma-separated rules to run (default: all). Valid: \(A11yRule.allCases.map(\.rawValue).joined(separator: ", "))."
        )
        var rules: String?

        @Option(
            name: .customLong("fail-on"),
            help: "Exit non-zero when a finding at this severity or above is present: error, warning, or none (default error)."
        )
        var failOn: String = "error"

        private static let failOnValues: Set<String> = ["error", "warning", "none"]

        func validate() throws {
            guard Self.failOnValues.contains(failOn) else {
                throw ValidationError("--fail-on must be one of: " + Self.failOnValues.sorted().joined(separator: ", ") + ".")
            }
            guard minTouchTarget > 0, minTouchTarget <= 200 else {
                throw ValidationError("--min-touch-target must be greater than 0 and at most 200.")
            }
            _ = try parseRules()
        }

        private func parseRules() throws -> Set<A11yRule> {
            guard let rules else { return Set(A11yRule.allCases) }
            let names = rules.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            }.filter { !$0.isEmpty }
            guard !names.isEmpty else {
                throw ValidationError("--rules was empty. Omit it to run every rule.")
            }
            var parsed: Set<A11yRule> = []
            for name in names {
                guard let rule = A11yRule(rawValue: name) else {
                    throw ValidationError(
                        "Unknown rule '\(name)'. Valid: " + A11yRule.allCases.map(\.rawValue).joined(separator: ", ") + ".")
                }
                parsed.insert(rule)
            }
            return parsed
        }

        func run() throws {
            let selectedRules = try parseRules()
            // ChildTree, not driver.describe: it carries the degenerate-tree
            // detection and the child-process respawn hedge that a one-shot audit
            // needs, since an empty tree would otherwise read as "no defects".
            let roots = try ChildTree.nodes(udid: udid, deep: !fast)
            if ChildTree.isDegenerate(roots) {
                throw ValidationError(
                    """
                    the accessibility tree came back empty; there is nothing to audit. \
                    Make sure an app is in the foreground on \(udid) and try `sipi describe-ui \(udid)` first.
                    """
                )
            }

            let findings = AccessibilityAudit.run(
                roots: roots,
                options: AccessibilityAudit.Options(minimumTouchTarget: minTouchTarget, rules: selectedRules)
            )
            let counts = AccessibilityAudit.counts(findings)
            let errors = counts[.error] ?? 0
            let warnings = counts[.warning] ?? 0

            if json {
                let object: [String: Any] = [
                    "udid": udid,
                    "deep": !fast,
                    "min-touch-target": minTouchTarget,
                    "rules": selectedRules.map(\.rawValue).sorted(),
                    "counts": ["error": errors, "warning": warnings, "total": findings.count],
                    "findings": findings.map(\.jsonObject)
                ]
                let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            } else {
                if findings.isEmpty {
                    print("no accessibility findings (\(selectedRules.count) rules over \(AccessibilityAudit.elementCount(roots: roots)) elements)")
                } else {
                    for finding in findings {
                        let target = finding.label ?? finding.identifier ?? finding.elementType ?? "element"
                        print("\(finding.severity.rawValue.uppercased()) [\(finding.rule.rawValue)] \(target): \(finding.message)")
                    }
                    print("\(errors) error(s), \(warnings) warning(s)")
                }
            }

            switch failOn {
            case "error" where errors > 0, "warning" where errors + warnings > 0:
                throw ExitCode.failure
            default:
                return
            }
        }
    }
}
