// simskillsgen — build-time generator for EmbeddedSkillsData.swift
//
// Invoked by the EmbedSkillsPlugin build-tool plugin on every `swift build`.
// Walks the three skill trees and emits a Swift source file that defines
// `EmbeddedSkills.entries` as a literal array of (relativePath, base64 bytes,
// executable bit). Embedding the data this way keeps the sipi binary
// self-contained: the curl|bash install ships one binary with the current
// skills baked in.
//
// Usage:
//   simskillsgen <skillsRoot> <outputFile> [skillDir ...]
//
//   skillsRoot  Directory that contains the skill subtrees (the in-package
//               `skills` symlink target, i.e. .claude/skills).
//   outputFile  Path to write the generated Swift file to.
//   skillDir    Optional explicit list of top-level skill directories to embed
//               (defaults to sipi-common, sipi-test, sipi-verify).
//
// Files are captured byte-for-byte; relative paths use POSIX separators so the
// setup step can recreate the tree on any host. The Unix executable bit is
// preserved per file so report-generator scripts stay runnable after setup.

import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(Data(
        "simskillsgen: usage: simskillsgen <skillsRoot> <outputFile> [skillDir ...]\n".utf8))
    exit(2)
}

let skillsRoot = arguments[1]
let outputFile = arguments[2]
let requestedSkillDirs: [String] = arguments.count > 3
    ? Array(arguments[3...])
    : ["sipi-common", "sipi-test", "sipi-verify"]

let fileManager = FileManager.default

struct CapturedFile {
    let relativePath: String
    let data: Data
    let isExecutable: Bool
}

/// Recursively collect every regular file under one skill directory, returning
/// paths relative to the skills root (e.g. "sipi-common/docs/build.md") with
/// POSIX separators.
///
/// The skills root is reached through an in-package symlink, so the enumerator
/// yields URLs with that symlink already resolved to the real .claude/skills
/// location. We therefore resolve the skill directory's real path and strip it
/// to compute the in-directory portion, then re-prefix with `skillDir` so the
/// embedded relative paths stay stable regardless of where the symlink points.
func collectFiles(skillDir: String, baseDirectory: String) -> [CapturedFile] {
    // Real (symlink-resolved) base so the enumerator's resolved URLs share the
    // same prefix and we can strip it deterministically.
    let resolvedBase = URL(fileURLWithPath: baseDirectory)
        .resolvingSymlinksInPath()
        .standardizedFileURL
    let basePrefix = resolvedBase.path.hasSuffix("/")
        ? resolvedBase.path
        : resolvedBase.path + "/"

    guard let enumerator = fileManager.enumerator(
        at: resolvedBase,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: []
    ) else {
        return []
    }

    var captured: [CapturedFile] = []

    for case let fileURL as URL in enumerator {
        let resolved = fileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: resolved.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            continue
        }

        let absolute = fileURL.standardizedFileURL.path
        let inDirectory: String
        if absolute.hasPrefix(basePrefix) {
            inDirectory = String(absolute.dropFirst(basePrefix.count))
        } else {
            inDirectory = fileURL.lastPathComponent
        }
        let relative = skillDir + "/" + inDirectory

        guard let data = fileManager.contents(atPath: resolved.path) else {
            FileHandle.standardError.write(Data(
                "simskillsgen: warning: could not read \(absolute)\n".utf8))
            continue
        }

        let isExecutable = fileManager.isExecutableFile(atPath: resolved.path)
        captured.append(CapturedFile(
            relativePath: relative,
            data: data,
            isExecutable: isExecutable
        ))
    }

    return captured
}

var allFiles: [CapturedFile] = []
for skillDir in requestedSkillDirs {
    let directory = skillsRoot + "/" + skillDir
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: directory, isDirectory: &isDirectory),
          isDirectory.boolValue else {
        FileHandle.standardError.write(Data(
            "simskillsgen: error: skill directory not found: \(directory)\n".utf8))
        exit(1)
    }
    allFiles.append(contentsOf: collectFiles(skillDir: skillDir, baseDirectory: directory))
}

// Stable, deterministic order so the generated file only changes when the
// skills change.
allFiles.sort { $0.relativePath < $1.relativePath }

guard !allFiles.isEmpty else {
    FileHandle.standardError.write(Data(
        "simskillsgen: error: no skill files found under \(skillsRoot)\n".utf8))
    exit(1)
}

var output = """
// EmbeddedSkillsData.swift
//
// GENERATED by simskillsgen via the EmbedSkillsPlugin build-tool plugin.
// DO NOT EDIT. Regenerated on every `swift build` from the skill files under
// .claude/skills (reached through the in-package `skills` symlink). Edits here
// are overwritten on the next build. To change embedded content, edit the skill
// files themselves and rebuild.

import Foundation

extension EmbeddedSkills {
    static let entries: [Entry] = [

"""

for file in allFiles {
    let base64 = file.data.base64EncodedString()
    let escapedPath = file.relativePath
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    output += "        Entry(\n"
    output += "            path: \"\(escapedPath)\",\n"
    output += "            data: Data(base64Encoded: \"\(base64)\")!,\n"
    output += "            isExecutable: \(file.isExecutable)\n"
    output += "        ),\n"
}

output += """
    ]
}

"""

do {
    try output.write(toFile: outputFile, atomically: true, encoding: .utf8)
} catch {
    FileHandle.standardError.write(Data(
        "simskillsgen: error: could not write \(outputFile): \(error)\n".utf8))
    exit(1)
}
