// SkillInstaller.swift
//
// Shared lifecycle logic for `sipi setup` / `sipi update` / `sipi uninstall`.
//
// SimPilot ships as a single prebuilt binary with the three skill trees
// (sipi-common, sipi-test, sipi-verify) embedded inside it (see EmbeddedSkills /
// the EmbedSkillsPlugin). `setup` materializes those embedded trees onto disk
// into BOTH ~/.claude/skills (Claude Code) and ~/.agents/skills (Codex); the
// binary is otherwise self-contained, so there is no git clone, no swift build,
// and no make on the user machine.
//
// CLEAN-FIRST: for each of the three skills, the existing on-disk directory is
// removed and recreated from the embedded files — and ONLY those three skills
// are touched. Other directories living alongside ours (e.g. AutoStore
// sipi-shots / publish) are never read, removed, or modified.
//
// No SimBridge, no Process(), no private frameworks — pure Foundation so the
// lifecycle stays host-portable and unit-testable. SimCore depends on SimSkills
// for the embedded payload.

import Foundation
import SimSkills

/// Materializes the embedded skill trees onto disk and records install metadata,
/// plus the inverse (removing exactly what setup created). Shared by the
/// `sipi setup`, `sipi update`, and `sipi uninstall` subcommands.
public enum SkillInstaller {

    /// The three skills SimPilot owns. ONLY these directories are ever created,
    /// cleaned, or removed under ~/.claude/skills and ~/.agents/skills. Any other
    /// directory (e.g. AutoStore's sipi-shots / publish) is out of scope and must
    /// never be touched.
    public static let skillNames = ["sipi-common", "sipi-test", "sipi-verify"]

    // MARK: - Well-known paths

    private static var homeDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    /// `~/.claude/skills` (Claude Code) and `~/.agents/skills` (Codex). Both are
    /// populated so a single setup serves both agents.
    public static var skillsRoots: [URL] {
        [
            homeDirectory.appendingPathComponent(".claude/skills", isDirectory: true),
            homeDirectory.appendingPathComponent(".agents/skills", isDirectory: true)
        ]
    }

    /// `~/.local/share/simpilot` — holds install.json (install metadata).
    public static var dataDirectory: URL {
        homeDirectory.appendingPathComponent(".local/share/simpilot", isDirectory: true)
    }

    /// `~/.local/share/simpilot/install.json`.
    public static var installMetadataFile: URL {
        dataDirectory.appendingPathComponent("install.json", isDirectory: false)
    }

    /// `~/.local/bin` — the conventional install location for the sipi binary.
    public static var binDirectory: URL {
        homeDirectory.appendingPathComponent(".local/bin", isDirectory: true)
    }

    /// `~/.local/bin/sipi`.
    public static var installedBinary: URL {
        binDirectory.appendingPathComponent("sipi", isDirectory: false)
    }

    // MARK: - Setup

    /// Outcome of a `setup` run, used to print a human-readable summary.
    public struct SetupResult: Sendable {
        /// Absolute skill directories that were (re)created, e.g.
        /// "~/.claude/skills/sipi-common".
        public var createdSkillDirs: [String]
        /// Number of files written across all skill trees.
        public var fileCount: Int
        /// Absolute path of the install metadata file written.
        public var metadataPath: String
        /// The version stamped into install.json.
        public var version: String
        /// True when ~/.local/bin is not on the current PATH (advice should print).
        public var binNotOnPath: Bool
    }

    /// Materialize the embedded skill trees into both agent skills roots and
    /// write install metadata. CLEAN-FIRST and idempotent: re-running produces
    /// the same on-disk state.
    ///
    /// For each of the three skills, in each root, the existing
    /// `<root>/<skill>` is removed (only those three) and recreated from the
    /// embedded files, restoring the Unix executable bit on scripts.
    @discardableResult
    public static func setup(version: String) throws -> SetupResult {
        let fileManager = FileManager.default
        var createdSkillDirs: [String] = []

        for root in skillsRoots {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

            // CLEAN: remove only our three skill directories under this root.
            for skill in skillNames {
                let skillDir = root.appendingPathComponent(skill, isDirectory: true)
                if fileManager.fileExists(atPath: skillDir.path) {
                    try fileManager.removeItem(at: skillDir)
                }
                try fileManager.createDirectory(at: skillDir, withIntermediateDirectories: true)
                createdSkillDirs.append(skillDir.path)
            }

            // RECREATE: write every embedded file under this root, restoring
            // the executable bit on scripts. Entry paths are relative to the
            // skills root (e.g. "sipi-common/SKILL.md") with POSIX separators.
            for entry in EmbeddedSkills.allEntries {
                let destination = root.appendingPathComponent(entry.path, isDirectory: false)
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try entry.data.write(to: destination, options: .atomic)
                if entry.isExecutable {
                    try fileManager.setAttributes(
                        [.posixPermissions: 0o755],
                        ofItemAtPath: destination.path
                    )
                }
            }
        }

        let metadataPath = try writeInstallMetadata(version: version)

        return SetupResult(
            createdSkillDirs: createdSkillDirs,
            fileCount: EmbeddedSkills.allEntries.count,
            metadataPath: metadataPath,
            version: version,
            binNotOnPath: !isBinDirectoryOnPath()
        )
    }

    /// Write `~/.local/share/simpilot/install.json` with the version, an ISO 8601
    /// install timestamp (with timezone offset), and the three skill names.
    /// Returns the absolute path written.
    @discardableResult
    private static func writeInstallMetadata(version: String) throws -> String {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: dataDirectory, withIntermediateDirectories: true)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let installedAt = formatter.string(from: Date())

        let metadata: [String: Any] = [
            "version": version,
            "installedAt": installedAt,
            "skills": skillNames
        ]
        let data = try JSONSerialization.data(
            withJSONObject: metadata,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: installMetadataFile, options: .atomic)
        return installMetadataFile.path
    }

    // MARK: - Uninstall

    /// Outcome of an `uninstall` run, used to print what was removed.
    public struct UninstallResult: Sendable {
        /// Absolute paths that were removed (skill dirs, data dir, binaries).
        public var removed: [String]
    }

    /// Remove exactly what setup created: the three skill directories from both
    /// agent roots, the ~/.local/share/simpilot data directory, and the sipi
    /// binary (~/.local/bin/sipi and, if different, the running executable path).
    /// Only our three skills are removed; sibling directories are left intact.
    @discardableResult
    public static func uninstall(runningExecutable: URL?) throws -> UninstallResult {
        let fileManager = FileManager.default
        var removed: [String] = []

        // 1. Our three skill directories in both roots (only ours).
        for root in skillsRoots {
            for skill in skillNames {
                let skillDir = root.appendingPathComponent(skill, isDirectory: true)
                if fileManager.fileExists(atPath: skillDir.path) {
                    try fileManager.removeItem(at: skillDir)
                    removed.append(skillDir.path)
                }
            }
        }

        // 2. The install metadata directory.
        if fileManager.fileExists(atPath: dataDirectory.path) {
            try fileManager.removeItem(at: dataDirectory)
            removed.append(dataDirectory.path)
        }

        // 3. The installed binary at ~/.local/bin/sipi.
        var removedPaths = Set<String>()
        if fileManager.fileExists(atPath: installedBinary.path) {
            try fileManager.removeItem(at: installedBinary)
            removed.append(installedBinary.path)
            removedPaths.insert(installedBinary.resolvingSymlinksInPath().path)
        }

        // 4. The running binary, if it is a different on-disk file (fine to
        //    unlink the running executable on macOS).
        if let running = runningExecutable {
            let resolved = running.resolvingSymlinksInPath()
            if fileManager.fileExists(atPath: resolved.path),
               !removedPaths.contains(resolved.path) {
                try fileManager.removeItem(at: resolved)
                removed.append(resolved.path)
            }
        }

        return UninstallResult(removed: removed)
    }

    // MARK: - PATH advice

    /// Whether ~/.local/bin is on the current process PATH.
    public static func isBinDirectoryOnPath() -> Bool {
        guard let path = ProcessInfo.processInfo.environment["PATH"] else { return false }
        let target = binDirectory.path
        return path.split(separator: ":").contains { String($0) == target }
    }

    /// A multi-line advice block to print when ~/.local/bin is not on PATH.
    public static var pathAdvice: String {
        """
        WARNING: \(binDirectory.path) is not on your PATH.
        Add it to your shell profile, e.g.:
          echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc
        """
    }
}
