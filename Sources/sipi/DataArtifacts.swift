// DataArtifacts.swift
//
// sipi-only capabilities around Simulator storage and evidence. Operations
// already provided by simctl remain direct simctl calls in the skills; these
// commands cover safe filesystem composition and artifact extraction.

import ArgumentParser
import Foundation
import SimCore
import SimShell

private enum DataArtifactCLIError: Error, CustomStringConvertible {
    case cleanupFailed([String])
    case noManifestEntries(String)

    var description: String {
        switch self {
        case .cleanupFailed(let failures): return failures.joined(separator: "\n")
        case .noManifestEntries(let root): return "manifest has no entries for selected root: \(root)"
        }
    }
}

enum DataArtifactCLI {
    static func kind(group: String?) -> ContainerKind {
        group.map(ContainerKind.group) ?? .data
    }

    static func root(udid: String, bundleID: String, group: String?) throws -> URL {
        try ContainerOperations.root(udid: udid, bundleID: bundleID, kind: kind(group: group))
    }

    static func writeJSON<T: Encodable>(_ value: T, to path: String? = nil) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        if let path {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            print(path)
        } else {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }

    static func loadManifest(_ path: String) throws -> FileMutationManifest {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return FileMutationManifest() }
        return try JSONDecoder().decode(FileMutationManifest.self, from: Data(contentsOf: url))
    }

    static func saveManifest(_ manifest: FileMutationManifest, path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(manifest).write(to: url, options: .atomic)
    }

    static func backupDirectory(for manifestPath: String) -> URL {
        let manifest = URL(fileURLWithPath: manifestPath)
        return manifest.deletingLastPathComponent()
            .appendingPathComponent(manifest.deletingPathExtension().lastPathComponent + "-backups")
    }

    static func manifestDirectory(for manifestPath: String) -> URL {
        URL(fileURLWithPath: manifestPath).deletingLastPathComponent()
    }

    static func cleanupManifest(path: String, selectedRoot: URL) throws -> (cleaned: Int, remaining: Int) {
        var manifest = try loadManifest(path)
        let canonicalRoot = selectedRoot.standardizedFileURL.resolvingSymlinksInPath()
        let selected = manifest.entries.filter {
            URL(fileURLWithPath: $0.root, isDirectory: true)
                .standardizedFileURL.resolvingSymlinksInPath() == canonicalRoot
        }
        guard !selected.isEmpty else {
            throw DataArtifactCLIError.noManifestEntries(canonicalRoot.path)
        }
        let scoped = FileMutationManifest(created: manifest.created, entries: selected)
        let failures = ContainerArtifacts.cleanup(
            scoped,
            allowedRoots: [canonicalRoot],
            allowedBackupRoot: manifestDirectory(for: path)
        )
        if !failures.isEmpty { throw DataArtifactCLIError.cleanupFailed(failures) }
        let selectedSet = Set(selected.map { "\($0.root)\u{0}\($0.path)\u{0}\($0.backup ?? "")" })
        manifest.entries.removeAll {
            selectedSet.contains("\($0.root)\u{0}\($0.path)\u{0}\($0.backup ?? "")")
        }
        try saveManifest(manifest, path: path)
        let trustedRecoveryRoot = manifestDirectory(for: path)
            .standardizedFileURL.resolvingSymlinksInPath()
        for recoveryPath in selected.flatMap({ [$0.backup, $0.marker].compactMap { $0 } }) {
            let recoveryURL = URL(fileURLWithPath: recoveryPath)
                .standardizedFileURL.resolvingSymlinksInPath()
            guard recoveryURL.path.hasPrefix(trustedRecoveryRoot.path + "/") else { continue }
            try? FileManager.default.removeItem(at: recoveryURL)
        }
        return (selected.count, manifest.entries.count)
    }
}

extension Sipi {
    struct ContainerCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "container",
            abstract: "Safely inspect or copy files beneath an app data/App Group container.",
            subcommands: [Path.self, List.self, Put.self, Pull.self, Snapshot.self, Diff.self, Inspect.self, Cleanup.self]
        )

        struct TargetOptions: ParsableArguments {
            @Argument(help: "Simulator UDID.") var udid: String
            @Argument(help: "Installed app bundle identifier.") var bundleID: String
            @Option(name: .long, help: "Specific App Group identifier. Omit for the data container.")
            var group: String?

            func root() throws -> URL {
                try DataArtifactCLI.root(udid: udid, bundleID: bundleID, group: group)
            }
        }

        struct Path: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Print the resolved container root.")
            @OptionGroup var target: TargetOptions
            func run() throws { print(try target.root().path) }
        }

        struct List: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "List direct children beneath a container path as JSON.")
            @OptionGroup var target: TargetOptions
            @Option(name: .long, help: "Relative directory inside the selected container.") var path: String?
            func run() throws { try DataArtifactCLI.writeJSON(ContainerOperations.list(root: target.root(), relative: path)) }
        }

        struct Put: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Copy a fixture into a container with reversible manifest backup.")
            @OptionGroup var target: TargetOptions
            @Argument(help: "Host source file or directory.") var source: String
            @Option(name: .long, help: "Relative destination inside the selected container.") var destination: String
            @Option(name: .long, help: "Mutation manifest path.") var manifest: String = "fixture-manifest.json"

            func run() throws {
                var value = try DataArtifactCLI.loadManifest(manifest)
                let placed = try ContainerArtifacts.put(
                    source: URL(fileURLWithPath: source),
                    root: target.root(),
                    destination: destination,
                    backupDirectory: DataArtifactCLI.backupDirectory(for: manifest),
                    manifest: &value,
                    persistManifest: { try DataArtifactCLI.saveManifest($0, path: manifest) }
                )
                print(placed.path)
            }
        }

        struct Pull: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Copy a container file or directory to the host.")
            @OptionGroup var target: TargetOptions
            @Argument(help: "Relative source path inside the selected container.") var path: String
            @Argument(help: "Host destination path.") var output: String
            func run() throws {
                try ContainerOperations.pull(
                    root: target.root(), relative: path, destination: URL(fileURLWithPath: output))
                print(output)
            }
        }

        struct Snapshot: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Capture container file metadata and hashes as JSON.")
            @OptionGroup var target: TargetOptions
            @Option(name: .long, help: "Output JSON path. Prints JSON when omitted.") var output: String?
            func run() throws {
                try DataArtifactCLI.writeJSON(ContainerArtifacts.snapshot(root: target.root()), to: output)
            }
        }

        struct Diff: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Compare two container snapshot JSON files.")
            @Argument(help: "Before snapshot JSON.") var before: String
            @Argument(help: "After snapshot JSON.") var after: String
            @Option(name: .long, help: "Output JSON path. Prints JSON when omitted.") var output: String?
            func run() throws {
                let decoder = JSONDecoder()
                let lhs = try decoder.decode(ContainerSnapshot.self, from: Data(contentsOf: URL(fileURLWithPath: before)))
                let rhs = try decoder.decode(ContainerSnapshot.self, from: Data(contentsOf: URL(fileURLWithPath: after)))
                try DataArtifactCLI.writeJSON(
                    try ContainerArtifacts.diff(before: lhs, after: rhs), to: output)
            }
        }

        struct Inspect: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Inspect metadata, text, JSON, plist, or SQLite content.")
            @OptionGroup var target: TargetOptions
            @Argument(help: "Relative file path inside the selected container.") var path: String
            @Option(name: .long, help: "metadata, text, json, plist, or sqlite.") var format: String = "metadata"
            @Option(name: .long, help: "JSON/plist key path, for example $.user.loggedIn.") var keyPath: String?
            @Option(name: .long, help: "Read-only SQLite query.") var query: String?
            func run() throws {
                try DataArtifactCLI.writeJSON(try ContainerOperations.inspect(
                    root: target.root(), relative: path, format: format,
                    keyPath: keyPath, sqliteQuery: query
                ))
            }
        }

        struct Cleanup: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Undo mutations recorded in a fixture manifest.")
            @OptionGroup var target: TargetOptions
            @Argument(help: "Mutation manifest JSON path.") var manifest: String
            func run() throws {
                let result = try DataArtifactCLI.cleanupManifest(
                    path: manifest, selectedRoot: target.root())
                print("cleaned \(result.cleaned); remaining \(result.remaining)")
            }
        }
    }

    struct FilesAppCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "files-app",
            abstract: "Experimental direct Files.app File Provider Storage operations.",
            subcommands: [Candidates.self, Put.self, Cleanup.self]
        )

        struct Candidates: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "List discovered File Provider Storage roots.")
            @Argument(help: "Simulator UDID.") var udid: String
            func run() throws { try DataArtifactCLI.writeJSON(try FileProviderStorage.candidates(udid: udid).map(\.path)) }
        }

        struct Put: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Copy a file into discovered File Provider Storage.")
            @Argument(help: "Simulator UDID.") var udid: String
            @Argument(help: "Host source file or directory.") var source: String
            @Option(name: .long, help: "Relative destination inside File Provider Storage.") var destination: String
            @Option(name: .long, help: "Explicit candidate returned by `files-app candidates`.") var storage: String?
            @Option(name: .long, help: "Mutation manifest path.") var manifest: String = "files-app-manifest.json"

            func run() throws {
                var value = try DataArtifactCLI.loadManifest(manifest)
                let root = try FileProviderStorage.select(udid: udid, explicitPath: storage)
                let placed = try ContainerArtifacts.put(
                    source: URL(fileURLWithPath: source), root: root, destination: destination,
                    backupDirectory: DataArtifactCLI.backupDirectory(for: manifest), manifest: &value,
                    persistManifest: { try DataArtifactCLI.saveManifest($0, path: manifest) })
                print(placed.path)
            }
        }

        struct Cleanup: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Undo Files.app mutations recorded in a manifest.")
            @Argument(help: "Simulator UDID.") var udid: String
            @Argument(help: "Mutation manifest JSON path.") var manifest: String
            @Option(name: .long, help: "Explicit candidate returned by `files-app candidates`.") var storage: String?
            func run() throws {
                let root = try FileProviderStorage.select(udid: udid, explicitPath: storage)
                let result = try DataArtifactCLI.cleanupManifest(path: manifest, selectedRoot: root)
                print("cleaned \(result.cleaned); remaining \(result.remaining)")
            }
        }
    }

    struct XCAppDataCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "xcappdata",
            abstract: "Create or validate an xcappdata fixture; install it with simctl directly.",
            subcommands: [Create.self, Validate.self]
        )

        struct Create: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Create xcappdata from an installed app data container.")
            @Argument(help: "Simulator UDID.") var udid: String
            @Argument(help: "Installed app bundle identifier.") var bundleID: String
            @Argument(help: "Output .xcappdata path.") var output: String
            func run() throws {
                let root = try ContainerOperations.root(udid: udid, bundleID: bundleID, kind: .data)
                try XCAppDataPackage.create(dataContainer: root, bundleID: bundleID, output: URL(fileURLWithPath: output))
                print(output)
            }
        }

        struct Validate: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Validate xcappdata structure and bundle ID.")
            @Argument(help: "Input .xcappdata path.") var path: String
            @Option(name: .long, help: "Expected bundle identifier.") var bundleID: String?
            func run() throws { print(try XCAppDataPackage.validate(URL(fileURLWithPath: path), expectedBundleID: bundleID)) }
        }
    }

    struct CrashEvidenceCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "crash-evidence",
            abstract: "Collect app-specific Simulator crash reports created after a timestamp."
        )
        @Argument(help: "Simulator UDID.") var udid: String
        @Argument(help: "App bundle identifier.") var bundleID: String
        @Argument(help: "Output directory.") var output: String
        @Option(name: .long, help: "ISO 8601 lower-bound timestamp. Defaults to now.") var since: String?

        func run() throws {
            let date: Date
            if let since {
                guard let parsed = ArtifactTime.parseISO8601(since) else {
                    throw ValidationError("--since must be ISO 8601 with timezone")
                }
                date = parsed
            } else {
                date = Date()
            }
            try DataArtifactCLI.writeJSON(try CrashEvidence.collect(
                udid: udid, bundleID: bundleID, since: date,
                outputDirectory: URL(fileURLWithPath: output, isDirectory: true)
            ))
        }
    }
}
