// Report.swift
//
// `sipi report` / `sipi verify-report` / `sipi validate` — the in-binary
// replacements for the loose interpreter scripts that used to live under the
// skill trees (generate_test_report.swift, generate_verify_report.swift,
// validate_simpilot_results.swift). Folding report/validate generation into the
// sipi binary keeps the curl|bash install a single self-contained download: the
// skill docs invoke `sipi …` instead of `swift "$SKILL_ROOT/scripts/…"`.
//
// All logic lives in SimCore (ReportGenerator / ResultValidator); these
// subcommands are thin CLI wrappers preserving the original output shape.

import ArgumentParser
import Foundation
import SimCore

// MARK: - report

extension Sipi {
    struct Report: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "report",
            abstract: "Generate report.html for a test run directory."
        )

        @Argument(help: "Test run directory (contains run.json).")
        var runDir: String

        func run() throws {
            do {
                let outPath = try ReportGenerator.writeTestReport(runDir: runDir)
                print("Report generated: \(outPath)")
            } catch let error as ReportGenerator.ReportError {
                FileHandle.standardError.write(Data((error.message + "\n").utf8))
                throw ExitCode.failure
            }
        }
    }
}

// MARK: - verify-report

extension Sipi {
    struct VerifyReport: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "verify-report",
            abstract: "Generate report.html for a verification directory."
        )

        @Argument(help: "Verification directory (contains the variant folders and findings.json).")
        var verifyDir: String

        @Option(name: .long, help: "Report title / page heading.")
        var title: String = "Verification"

        @Option(name: .long, help: "Status fallback (ok|issue) used only when findings.json is missing.")
        var status: String?

        func run() throws {
            do {
                let outPath = try ReportGenerator.writeVerifyReport(
                    verifyDir: verifyDir,
                    title: title,
                    statusOverride: status
                )
                print("Report generated: \(outPath)")
            } catch let error as ReportGenerator.ReportError {
                FileHandle.standardError.write(Data((error.message + "\n").utf8))
                throw ExitCode.failure
            }
        }
    }
}

// MARK: - validate

extension Sipi {
    struct Validate: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "validate",
            abstract: "Validate the JSON files in a .simpilot workspace."
        )

        @Argument(help: "Path to the .simpilot workspace directory.")
        var path: String

        func run() throws {
            let outcome: ResultValidator.ValidationOutcome
            do {
                outcome = try ResultValidator.validate(workspace: path)
            } catch let error as ResultValidator.ValidationError {
                FileHandle.standardError.write(Data((error.message + "\n").utf8))
                throw ExitCode.failure
            }

            for w in outcome.warnings {
                FileHandle.standardError.write(Data(("WARNING: \(w)\n").utf8))
            }

            if !outcome.isValid {
                for e in outcome.errors {
                    FileHandle.standardError.write(Data((e + "\n").utf8))
                }
                throw ExitCode.failure
            }

            print("OK")
        }
    }
}
