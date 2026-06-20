// Setup.swift
//
// `sipi setup` — materialize the embedded skill trees onto disk.
//
// The prebuilt sipi binary ships the three skills (sipi-common, sipi-test,
// sipi-verify) baked in. `setup` recreates them under BOTH ~/.claude/skills
// (Claude Code) and ~/.agents/skills (Codex) and records install metadata to
// ~/.local/share/simpilot/install.json. CLEAN-FIRST and idempotent — re-running
// is the supported refresh path and only ever touches our own three skills.
//
// All of the heavy lifting lives in SimCore.SkillInstaller so `setup` and
// `update` share one implementation.

import ArgumentParser
import Foundation
import SimCore

extension Sipi {
    struct Setup: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "setup",
            abstract: "Install the embedded skills into Claude Code and Codex (idempotent)."
        )

        func run() throws {
            let result = try SkillInstaller.setup(version: sipiVersion)

            print("SimPilot setup complete (sipi \(result.version)).")
            print("  Skills installed (\(result.fileCount) files):")
            for dir in result.createdSkillDirs {
                print("    \(dir)")
            }
            print("  Metadata: \(result.metadataPath)")

            if result.binNotOnPath {
                print("")
                FileHandle.standardError.write(Data((SkillInstaller.pathAdvice + "\n").utf8))
            }
        }
    }
}
