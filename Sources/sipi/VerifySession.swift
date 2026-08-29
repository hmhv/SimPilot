// VerifySession.swift
//
// Deterministic verification artifact manager. The model still decides what to
// inspect, but the directory layout, screenshot capture, findings, and report
// generation are owned by sipi.

import ArgumentParser
import Foundation
import SimCore
import SimNative
import SimShell

private struct VerifySessionError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

private enum VerifySessionUtil {
    static let variants = ["iphone-light", "iphone-dark", "ipad-light", "ipad-dark"]

    static func slug(_ raw: String) -> String {
        let lower = raw.lowercased()
        let mapped = lower.map { ch -> Character in
            if ch.isLetter || ch.isNumber { return ch }
            return "-"
        }
        return String(mapped).split(separator: "-").joined(separator: "-")
    }

    static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter.string(from: Date())
    }

    /// Read a JSON array file for an append. `init` always creates findings.json
    /// and checks.json, so at append time a MISSING file means the session was
    /// deleted/tampered — an error, not a silent fresh `[]` (which would hide the
    /// loss and overwrite whatever the user expected). A present-but-unparseable
    /// file is likewise an error, never reset to `[]`.
    static func readArrayStrict(path: String) throws -> [[String: Any]] {
        guard FileManager.default.fileExists(atPath: path) else {
            throw VerifySessionError("\(path) is missing (run `verify-session init` first)")
        }
        guard let data = FileManager.default.contents(atPath: path) else {
            throw VerifySessionError("cannot read \(path)")
        }
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw VerifySessionError("\(path) is not a JSON array of objects (refusing to overwrite it)")
        }
        return array
    }

    static func writeArray(_ array: [[String: Any]], path: String) throws {
        let data = try JSONSerialization.data(withJSONObject: array, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: path))
    }

    /// Serialize a read-modify-write against a per-directory advisory file lock,
    /// so concurrent `capture` / `finding` processes cannot both read the same
    /// old array and lose one another's append (last-writer-wins).
    static func withLock<T>(dir: String, _ body: () throws -> T) throws -> T {
        let lockPath = dir + "/.lock"
        let fd = open(lockPath, O_CREAT | O_RDWR, 0o644)
        if fd < 0 { throw VerifySessionError("cannot open lock file \(lockPath)") }
        defer { close(fd) }
        if flock(fd, LOCK_EX) != 0 { throw VerifySessionError("cannot acquire lock on \(lockPath)") }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }
}

extension Sipi {
    struct VerifySession: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "verify-session",
            abstract: "Create and finalize deterministic verification artifacts.",
            subcommands: [Init.self, Capture.self, Finding.self, Finalize.self]
        )

        struct Init: ParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "init",
                abstract: "Create a verification directory with variant folders and empty findings."
            )

            @Argument(help: "Short verification description.")
            var description: String

            @Option(name: .long, help: "Path to the .simpilot workspace.")
            var workspace: String = ".simpilot"

            func run() throws {
                let slug = VerifySessionUtil.slug(description)
                let base = workspace + "/verify/" + VerifySessionUtil.timestamp() + "_" + (slug.isEmpty ? "session" : slug)
                let fm = FileManager.default
                try fm.createDirectory(atPath: workspace + "/verify", withIntermediateDirectories: true)
                // The timestamp is second-precision, so two inits with the same
                // description in the same second would collide. Claim a directory
                // ATOMICALLY: createDirectory(withIntermediateDirectories: false)
                // throws fileWriteFileExists if it already exists, so concurrent
                // processes never share (and clobber) a directory — a plain
                // fileExists check would race between the check and the create.
                var dir = base
                var suffix = 2
                while true {
                    do {
                        try fm.createDirectory(atPath: dir, withIntermediateDirectories: false)
                        break
                    } catch let error as CocoaError where error.code == .fileWriteFileExists {
                        dir = base + "-\(suffix)"
                        suffix += 1
                        if suffix > 10_000 { throw error }
                    }
                }
                for variant in VerifySessionUtil.variants {
                    try fm.createDirectory(atPath: dir + "/" + variant, withIntermediateDirectories: true)
                }
                try VerifySessionUtil.writeArray([], path: dir + "/findings.json")
                try VerifySessionUtil.writeArray([], path: dir + "/checks.json")
                print("Verify results: \(URL(fileURLWithPath: dir).path)")
            }
        }

        struct Capture: ParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "capture",
                abstract: "Capture one screenshot into a verification variant folder."
            )

            @Argument(help: "Verification directory.")
            var verifyDir: String

            @Argument(help: "Variant folder, e.g. iphone-light, ipad-dark.")
            var variant: String

            @Argument(help: "Check name; always normalized to a slug filename (NNN_<check>.png with --index, else <check>.png).")
            var check: String

            @Option(name: .long, help: "Simulator UDID. Defaults to the first booted simulator.")
            var device: String?

            @Option(name: .long, help: "1-based screenshot index for aligned grids.")
            var index: Int?

            @Option(name: .long, help: "Appearance override: light or dark.")
            var appearance: String?

            func run() throws {
                guard VerifySessionUtil.variants.contains(variant) else {
                    throw ValidationError("variant must be one of \(VerifySessionUtil.variants.joined(separator: ", "))")
                }
                let driver = NativeDriver()
                let udid: String
                if let device {
                    udid = device
                } else if let booted = try driver.devices().first(where: { $0.booted }) {
                    udid = booted.udid
                } else {
                    throw ValidationError("No booted simulator found. Pass --device or boot a simulator.")
                }
                if let appearance {
                    try SimShell.setAppearance(udid: udid, appearance: appearance)
                    usleep(500 * 1000)
                }
                // Always derive the filename from a slug of the check name so a
                // check like "../../evil.png" cannot escape the variant folder.
                let base = check.hasSuffix(".png") ? String(check.dropLast(4)) : check
                let slugged = VerifySessionUtil.slug(base)
                let safe = slugged.isEmpty ? "capture" : slugged
                let filename = index.map { String(format: "%03d_%@.png", $0, safe) } ?? (safe + ".png")
                let outDir = verifyDir + "/" + variant
                try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
                try driver.screenshot(to: URL(fileURLWithPath: outDir + "/" + filename), udid: udid)

                try VerifySessionUtil.withLock(dir: verifyDir) {
                    var checks = try VerifySessionUtil.readArrayStrict(path: verifyDir + "/checks.json")
                    if !checks.contains(where: { $0["filename"] as? String == filename }) {
                        checks.append(["filename": filename, "check": check])
                        try VerifySessionUtil.writeArray(checks, path: verifyDir + "/checks.json")
                    }
                }
                print(outDir + "/" + filename)
            }
        }

        struct Finding: ParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "finding",
                abstract: "Append one finding to findings.json."
            )

            @Argument(help: "Verification directory.")
            var verifyDir: String

            @Option(name: .long, help: "Check name.")
            var check: String

            @Option(name: .long, help: "Variant, e.g. ipad-dark.")
            var variant: String

            @Option(name: .long, help: "Issue text.")
            var issue: String

            func run() throws {
                try VerifySessionUtil.withLock(dir: verifyDir) {
                    var findings = try VerifySessionUtil.readArrayStrict(path: verifyDir + "/findings.json")
                    findings.append(["check": check, "variant": variant, "issue": issue])
                    try VerifySessionUtil.writeArray(findings, path: verifyDir + "/findings.json")
                }
                print("Finding recorded: \(check) \(variant)")
            }
        }

        struct Finalize: ParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "finalize",
                abstract: "Write summary.json for a verification, and optionally report.html."
            )

            @Argument(help: "Verification directory.")
            var verifyDir: String

            @Option(name: .long, help: "Report title.")
            var title: String = "Verification"

            @Flag(name: .customLong("html"), help: "Also render report.html. Off by default; summary.json, checks.json and findings.json are always written.")
            var html = false

            func run() throws {
                // Refresh a page that is already there even without --html. The
                // flag asks for the page to EXIST; leaving a stale one beside a
                // rewritten summary is worse than either writing it or not —
                // summary.json would name a page that contradicts it.
                let pageExists = FileManager.default.fileExists(atPath: verifyDir + "/report.html")
                if html || pageExists {
                    let out = try ReportGenerator.writeVerifyReport(verifyDir: verifyDir, title: title)
                    print("Report generated: \(out)")
                } else {
                    let out = try ReportGenerator.writeVerifySummary(verifyDir: verifyDir, title: title)
                    print("Summary generated: \(out)")
                }
                print("Verify results: \(URL(fileURLWithPath: verifyDir).path)")
            }
        }
    }
}
