// EmbeddedSkills.swift
//
// Public API surface for the skill trees embedded into the sipi binary at build
// time. The actual entries live in the generated EmbeddedSkillsData.swift, which
// the EmbedSkillsPlugin build-tool plugin regenerates on every `swift build`
// from the real skill files under .claude/skills (read through the in-package
// `skills` symlink). Keeping the binary self-contained means the curl|bash
// install ships a single download with the current skills baked in — no git
// clone, no separate skill payload.
//
// The generated half exposes `EmbeddedSkills.entries`, which this file surfaces
// as `EmbeddedSkills.all`. Setup recreates the on-disk skill tree from these
// entries, preserving relative paths and the executable bit on scripts.

import Foundation

/// The three skill trees (sipi-common, sipi-test, sipi-verify) captured at build
/// time and shipped inside the sipi binary. `all` is the full list of files as
/// (relativePath, bytes); `executablePaths` marks which of those relative paths
/// carried a Unix executable bit in the source tree so setup can restore it.
public enum EmbeddedSkills {

    /// One embedded skill file.
    public struct Entry: Sendable {
        /// Path relative to the skills root, e.g. "sipi-common/SKILL.md".
        /// POSIX-style separators; stable across platforms.
        public let path: String
        /// Raw file bytes, byte-for-byte identical to the source file.
        public let data: Data
        /// Whether the source file carried a Unix executable bit (scripts).
        public let isExecutable: Bool

        public init(path: String, data: Data, isExecutable: Bool) {
            self.path = path
            self.data = data
            self.isExecutable = isExecutable
        }
    }

    /// Every embedded skill file as (path, data). Order is the generated order
    /// (sorted by relative path) and is stable for a given source tree.
    public static var all: [(path: String, data: Data)] {
        entries.map { ($0.path, $0.data) }
    }

    /// Full entries including the executable bit. Use this for setup when the
    /// executable flag matters; use `all` for plain (path, data) access.
    public static var allEntries: [Entry] { entries }

    /// Relative paths whose source files were executable (e.g. the report
    /// generator scripts). Setup restores 0o755 on these.
    public static var executablePaths: [String] {
        entries.filter { $0.isExecutable }.map { $0.path }
    }
}
