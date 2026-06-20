// EmbedSkillsPlugin — SwiftPM build-tool plugin
//
// Runs on every `swift build` for the SimSkills target. It invokes the
// `simskillsgen` generator executable, pointing it at the in-package `skills`
// symlink (which resolves to .claude/skills outside the package) and at a file
// in the plugin work directory. The generator emits EmbeddedSkillsData.swift,
// which SwiftPM then compiles into SimSkills.
//
// Every skill file is declared as an `inputFiles` of the build command, so
// SwiftPM re-runs the generator whenever any skill changes. Without that,
// SwiftPM would cache the output and the embedded payload could go stale
// relative to the source tree (a content edit would not trigger a rebuild).
//
// The skills live outside the package; reading them from a build-tool plugin
// command works because the in-package symlink keeps the read inside the
// package's input scope (verified: the SwiftPM sandbox follows the symlink to
// the real files).

import PackagePlugin
import Foundation

@main
struct EmbedSkillsPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        // The `skills` symlink lives at the root of the SimSkills target.
        let skillsRoot = target.directory.appending("skills")
        let output = context.pluginWorkDirectory.appending("EmbeddedSkillsData.swift")
        let generator = try context.tool(named: "simskillsgen")

        // Enumerate every skill file (through the symlink) and declare them as
        // inputs so SwiftPM invalidates the cached output when a skill changes.
        // Re-enumerated on each build, so added/removed files are picked up too.
        // Done in a synchronous helper because iterating a DirectoryEnumerator
        // calls makeIterator, which is unavailable from an async context (an error
        // in the Swift 6 language mode) and createBuildCommands is async.
        let inputFiles = Self.skillInputFiles(under: skillsRoot.string)

        return [
            .buildCommand(
                displayName: "Embedding skill trees into SimSkills",
                executable: generator.path,
                arguments: [
                    skillsRoot.string,
                    output.string
                ],
                inputFiles: inputFiles,
                outputFiles: [output]
            )
        ]
    }

    /// Every regular file under `root` (following the symlink), as plugin input
    /// paths. Kept synchronous so the DirectoryEnumerator iteration stays out of
    /// the async `createBuildCommands`: makeIterator is unavailable from an async
    /// context (an error in the Swift 6 language mode).
    private static func skillInputFiles(under root: String) -> [Path] {
        let fm = FileManager.default
        guard let walker = fm.enumerator(atPath: root) else { return [] }
        var inputFiles: [Path] = []
        for case let relative as String in walker {
            let fullPath = root + "/" + relative
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: fullPath, isDirectory: &isDirectory), !isDirectory.boolValue {
                inputFiles.append(Path(fullPath))
            }
        }
        return inputFiles
    }
}
