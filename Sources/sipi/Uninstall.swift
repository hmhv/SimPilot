// Uninstall.swift
//
// `sipi uninstall` — remove everything `setup` installed, natively (no external
// scripts). Removes the three skill directories from both ~/.claude/skills and
// ~/.agents/skills (only ours — sibling dirs like AutoStore sipi-shots/publish
// are left intact), the ~/.local/share/simpilot data directory, and the sipi
// binary itself (~/.local/bin/sipi and, if different, the running executable
// path resolved from CommandLine.arguments[0]). It is fine to unlink the running
// binary on macOS.

import ArgumentParser
import Foundation
import SimCore

extension Sipi {
    struct Uninstall: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "uninstall",
            abstract: "Remove SimPilot skills, install metadata, and the sipi binary."
        )

        func run() throws {
            let result = try SkillInstaller.uninstall(runningExecutable: Self.runningExecutableURL())

            if result.removed.isEmpty {
                print("Nothing to remove — SimPilot was not installed.")
            } else {
                print("SimPilot uninstalled. Removed:")
                for path in result.removed {
                    print("    \(path)")
                }
            }
        }

        /// Resolve the on-disk path of the running `sipi` executable from
        /// `CommandLine.arguments[0]`, following symlinks (realpath). Returns nil
        /// if it cannot be resolved to an existing file.
        static func runningExecutableURL() -> URL? {
            guard let argv0 = CommandLine.arguments.first, !argv0.isEmpty else { return nil }

            let candidate: URL
            if argv0.contains("/") {
                // A path (absolute or relative) — resolve against cwd if relative.
                candidate = URL(fileURLWithPath: argv0)
            } else {
                // A bare command name found via PATH — locate it.
                guard let resolved = locateOnPath(argv0) else { return nil }
                candidate = resolved
            }

            let real = candidate.resolvingSymlinksInPath().standardizedFileURL
            return FileManager.default.fileExists(atPath: real.path) ? real : nil
        }

        /// Find a bare command name on PATH, returning the first match.
        private static func locateOnPath(_ name: String) -> URL? {
            guard let path = ProcessInfo.processInfo.environment["PATH"] else { return nil }
            for dir in path.split(separator: ":") {
                let candidate = URL(fileURLWithPath: String(dir), isDirectory: true)
                    .appendingPathComponent(name, isDirectory: false)
                if FileManager.default.isExecutableFile(atPath: candidate.path) {
                    return candidate
                }
            }
            return nil
        }
    }
}
