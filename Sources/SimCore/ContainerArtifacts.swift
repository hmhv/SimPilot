// ContainerArtifacts.swift
//
// Pure filesystem models and operations shared by the container CLI and the
// deterministic harness. This file never invokes simctl: SimShell resolves the
// simulator-owned roots, then hands those roots to these path-safe primitives.

import CryptoKit
import Foundation

public enum ArtifactTime {
    /// ISO 8601 with an explicit timezone offset, matching the repository's run
    /// and result timestamp contract.
    public static func iso(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        return formatter.string(from: date)
    }

    public static func parseISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

public enum SafeRelativePathError: Error, CustomStringConvertible, Equatable {
    case empty
    case absolute(String)
    case traversal(String)
    case nul
    case escapesRoot(String)
    case symbolicLink(String)

    public var description: String {
        switch self {
        case .empty: return "relative path must not be empty"
        case .absolute(let path): return "absolute path is not allowed: \(path)"
        case .traversal(let path): return "path traversal is not allowed: \(path)"
        case .nul: return "path contains a NUL byte"
        case .escapesRoot(let path): return "path escapes the selected container: \(path)"
        case .symbolicLink(let path): return "symbolic links are not allowed in container paths: \(path)"
        }
    }
}

public enum SafeRelativePath {
    /// Normalize a user-authored relative path. Empty components and `.` are
    /// removed, while absolute paths and `..` are rejected.
    public static func normalize(_ raw: String) throws -> String {
        if raw.contains("\u{0}") { throw SafeRelativePathError.nul }
        if raw.isEmpty { throw SafeRelativePathError.empty }
        if raw.hasPrefix("/") || (raw as NSString).isAbsolutePath {
            throw SafeRelativePathError.absolute(raw)
        }
        var components: [String] = []
        for component in raw.split(separator: "/", omittingEmptySubsequences: true).map(String.init) {
            if component == "." { continue }
            if component == ".." { throw SafeRelativePathError.traversal(raw) }
            components.append(component)
        }
        guard !components.isEmpty else { throw SafeRelativePathError.empty }
        return components.joined(separator: "/")
    }

    /// Resolve a path beneath `root`, refusing symlinks in every existing path
    /// component. The leaf may not exist yet, which is required for fixture puts.
    public static func resolve(root: URL, relative raw: String) throws -> URL {
        let relative = try normalize(raw)
        let fm = FileManager.default
        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        var cursor = canonicalRoot
        for component in relative.split(separator: "/").map(String.init) {
            cursor.appendPathComponent(component)
            if fm.fileExists(atPath: cursor.path) {
                let values = try cursor.resourceValues(forKeys: [.isSymbolicLinkKey])
                if values.isSymbolicLink == true {
                    throw SafeRelativePathError.symbolicLink(cursor.path)
                }
            }
        }
        let standardized = cursor.standardizedFileURL
        let rootPrefix = canonicalRoot.path.hasSuffix("/") ? canonicalRoot.path : canonicalRoot.path + "/"
        guard standardized.path.hasPrefix(rootPrefix) else {
            throw SafeRelativePathError.escapesRoot(raw)
        }
        return standardized
    }
}

public struct ContainerFileRecord: Codable, Equatable, Sendable {
    public var path: String
    public var size: UInt64
    public var sha256: String
    public var modified: String?

    public init(path: String, size: UInt64, sha256: String, modified: String? = nil) {
        self.path = path
        self.size = size
        self.sha256 = sha256
        self.modified = modified
    }
}

public struct ContainerSnapshot: Codable, Equatable, Sendable {
    public var created: String
    public var root: String
    public var files: [ContainerFileRecord]
    public var errors: [ContainerSnapshotError]?

    public init(
        created: String = ArtifactTime.iso(),
        root: String,
        files: [ContainerFileRecord],
        errors: [ContainerSnapshotError]? = nil
    ) {
        self.created = created
        self.root = root
        self.files = files.sorted { $0.path < $1.path }
        self.errors = errors?.isEmpty == true ? nil : errors
    }
}

public struct ContainerSnapshotError: Codable, Equatable, Sendable {
    public var path: String
    public var error: String

    public init(path: String, error: String) {
        self.path = path
        self.error = error
    }
}

public struct ContainerDiff: Codable, Equatable, Sendable {
    public var created: String
    public var added: [ContainerFileRecord]
    public var removed: [ContainerFileRecord]
    public var changed: [ContainerFileRecord]
    public var skipped: [ContainerSnapshotError]?

    public init(
        created: String = ArtifactTime.iso(),
        added: [ContainerFileRecord],
        removed: [ContainerFileRecord],
        changed: [ContainerFileRecord],
        skipped: [ContainerSnapshotError]? = nil
    ) {
        self.created = created
        self.added = added.sorted { $0.path < $1.path }
        self.removed = removed.sorted { $0.path < $1.path }
        self.changed = changed.sorted { $0.path < $1.path }
        self.skipped = skipped?.isEmpty == true ? nil : skipped?.sorted { $0.path < $1.path }
    }
}

public struct FileMutationEntry: Codable, Equatable, Sendable {
    public var root: String
    public var path: String
    public var backup: String?
    public var created: Bool
    public var marker: String?
    public var token: String?
    public var createdDirectories: [String]?

    public init(
        root: String,
        path: String,
        backup: String?,
        created: Bool,
        marker: String? = nil,
        token: String? = nil,
        createdDirectories: [String]? = nil
    ) {
        self.root = root
        self.path = path
        self.backup = backup
        self.created = created
        self.marker = marker
        self.token = token
        self.createdDirectories = createdDirectories
    }
}

public struct FileMutationManifest: Codable, Equatable, Sendable {
    public var created: String
    public var entries: [FileMutationEntry]

    public init(created: String = ArtifactTime.iso(), entries: [FileMutationEntry] = []) {
        self.created = created
        self.entries = entries
    }
}

public enum ContainerArtifactError: Error, CustomStringConvertible {
    case copyFailed(String)
    case invalidManifest(String)
    case snapshotRootMismatch(String, String)

    public var description: String {
        switch self {
        case .copyFailed(let message): return message
        case .invalidManifest(let message): return message
        case .snapshotRootMismatch(let before, let after):
            return "cannot diff snapshots from different roots: \(before) and \(after)"
        }
    }
}

public enum ContainerArtifacts {
    public static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func snapshot(root: URL) throws -> ContainerSnapshot {
        let fm = FileManager.default
        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        guard let enumerator = fm.enumerator(atPath: canonicalRoot.path) else {
            throw CocoaError(.fileReadUnknown)
        }
        var files: [ContainerFileRecord] = []
        var errors: [ContainerSnapshotError] = []
        for case let relative as String in enumerator {
            do {
                let url = canonicalRoot.appendingPathComponent(relative)
                let attrs = try fm.attributesOfItem(atPath: url.path)
                if attrs[.type] as? FileAttributeType == .typeSymbolicLink {
                    enumerator.skipDescendants()
                    continue
                }
                guard attrs[.type] as? FileAttributeType == .typeRegular else { continue }
                files.append(ContainerFileRecord(
                    path: relative,
                    size: (attrs[.size] as? NSNumber)?.uint64Value ?? 0,
                    sha256: try sha256(url),
                    modified: (attrs[.modificationDate] as? Date).map(ArtifactTime.iso)
                ))
            } catch {
                errors.append(ContainerSnapshotError(path: relative, error: String(describing: error)))
            }
        }
        return ContainerSnapshot(root: canonicalRoot.path, files: files, errors: errors)
    }

    public static func diff(before: ContainerSnapshot, after: ContainerSnapshot) throws -> ContainerDiff {
        guard before.root == after.root else {
            throw ContainerArtifactError.snapshotRootMismatch(before.root, after.root)
        }
        let old = Dictionary(before.files.map { ($0.path, $0) }, uniquingKeysWith: { _, last in last })
        let new = Dictionary(after.files.map { ($0.path, $0) }, uniquingKeysWith: { _, last in last })
        let skipped = (before.errors ?? []) + (after.errors ?? [])
        let skippedPaths = Set(skipped.map(\.path))
        let oldKeys = Set(old.keys).subtracting(skippedPaths)
        let newKeys = Set(new.keys).subtracting(skippedPaths)
        let added = newKeys.subtracting(oldKeys).compactMap { new[$0] }
        let removed = oldKeys.subtracting(newKeys).compactMap { old[$0] }
        let changed = newKeys.intersection(oldKeys).compactMap { key -> ContainerFileRecord? in
            guard let lhs = old[key], let rhs = new[key],
                  lhs.sha256 != rhs.sha256 || lhs.size != rhs.size else { return nil }
            return rhs
        }
        return ContainerDiff(added: added, removed: removed, changed: changed, skipped: skipped)
    }

    /// Copy a fixture into a root and append a reversible entry to `manifest`.
    /// Existing files are backed up under `backupDirectory` before replacement.
    @discardableResult
    public static func put(
        source: URL,
        root: URL,
        destination: String,
        backupDirectory: URL,
        manifest: inout FileMutationManifest,
        persistManifest: ((FileMutationManifest) throws -> Void)? = nil
    ) throws -> URL {
        let fm = FileManager.default
        var sourceIsDirectory: ObjCBool = false
        guard fm.fileExists(atPath: source.path, isDirectory: &sourceIsDirectory) else {
            throw CocoaError(.fileNoSuchFile)
        }
        try rejectSymlinksAndSpecialFiles(in: source, isDirectory: sourceIsDirectory.boolValue)
        let normalizedDestination = try SafeRelativePath.normalize(destination)
        let target = try SafeRelativePath.resolve(root: root, relative: destination)
        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        var createdDirectories: [String] = []
        var parentCursor = canonicalRoot
        var parentParts: [String] = []
        for component in normalizedDestination.split(separator: "/").dropLast().map(String.init) {
            parentParts.append(component)
            parentCursor.appendPathComponent(component, isDirectory: true)
            if !fm.fileExists(atPath: parentCursor.path) {
                createdDirectories.append(parentParts.joined(separator: "/"))
            }
        }
        var targetIsDirectory: ObjCBool = false
        let existed = fm.fileExists(atPath: target.path, isDirectory: &targetIsDirectory)
        var backup: String?
        var marker: String?
        var token: String?
        if existed {
            try fm.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
            let backupURL = backupDirectory.appendingPathComponent(UUID().uuidString)
            do {
                try fm.copyItem(at: target, to: backupURL)
            } catch {
                try? fm.removeItem(at: backupURL)
                throw error
            }
            backup = backupURL.path
        } else {
            try fm.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
            let markerURL = backupDirectory.appendingPathComponent(UUID().uuidString + ".created")
            let markerToken = UUID().uuidString
            try Data(markerToken.utf8).write(to: markerURL, options: .atomic)
            marker = markerURL.path
            token = markerToken
        }
        do {
            try fm.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            if let backup { try? fm.removeItem(atPath: backup) }
            if let marker { try? fm.removeItem(atPath: marker) }
            removeEmptyDirectories(createdDirectories, root: canonicalRoot)
            throw error
        }
        let entry = FileMutationEntry(
            root: canonicalRoot.path,
            path: normalizedDestination,
            backup: backup,
            created: !existed,
            marker: marker,
            token: token,
            createdDirectories: createdDirectories.isEmpty ? nil : createdDirectories
        )
        manifest.entries.append(entry)
        do {
            try persistManifest?(manifest)
        } catch {
            manifest.entries.removeLast()
            if let backup { try? fm.removeItem(atPath: backup) }
            if let marker { try? fm.removeItem(atPath: marker) }
            removeEmptyDirectories(createdDirectories, root: canonicalRoot)
            throw error
        }
        do {
            if existed { try fm.removeItem(at: target) }
            try fm.copyItem(at: source, to: target)
        } catch {
            let copyError = error
            var rollbackError: Error?
            do {
                if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
                if let backup {
                    try fm.copyItem(at: URL(fileURLWithPath: backup), to: target)
                }
            } catch {
                rollbackError = error
            }
            if rollbackError == nil {
                manifest.entries.removeLast()
                do {
                    try persistManifest?(manifest)
                    if let backup { try? fm.removeItem(atPath: backup) }
                    if let marker { try? fm.removeItem(atPath: marker) }
                    removeEmptyDirectories(createdDirectories, root: canonicalRoot)
                } catch {
                    throw ContainerArtifactError.copyFailed(
                        "copy failed (\(copyError)); original was restored, but manifest update failed (\(error))"
                    )
                }
                throw copyError
            }
            throw ContainerArtifactError.copyFailed(
                "copy failed (\(copyError)); rollback also failed (\(rollbackError!)); recovery entry remains in the manifest"
            )
        }
        return target
    }

    /// Undo manifest entries in reverse order. Both mutation roots and backup
    /// files must remain beneath caller-provided trusted directories, so an
    /// edited manifest cannot turn cleanup into an arbitrary host filesystem
    /// delete or copy operation.
    public static func cleanup(
        _ manifest: FileMutationManifest,
        allowedRoots: [URL],
        allowedBackupRoot: URL? = nil
    ) -> [String] {
        let fm = FileManager.default
        var failures: [String] = []
        let trustedRoots = allowedRoots.map { $0.standardizedFileURL.resolvingSymlinksInPath() }
        let trustedBackupRoot = allowedBackupRoot?.standardizedFileURL.resolvingSymlinksInPath()
        for entry in manifest.entries.reversed() {
            do {
                let root = URL(fileURLWithPath: entry.root, isDirectory: true)
                    .standardizedFileURL.resolvingSymlinksInPath()
                guard trustedRoots.contains(where: { root == $0 }) else {
                    throw SafeRelativePathError.escapesRoot(entry.root)
                }
                let target = try resolveMutationTarget(root: root, relative: entry.path)
                if entry.created {
                    guard entry.backup == nil,
                          let marker = entry.marker,
                          let token = entry.token else {
                        throw ContainerArtifactError.invalidManifest(
                            "created entry has no recovery marker: \(entry.path)")
                    }
                    let markerURL = URL(fileURLWithPath: marker)
                        .standardizedFileURL.resolvingSymlinksInPath()
                    guard let trustedBackupRoot,
                          isContained(markerURL, by: trustedBackupRoot),
                          fm.fileExists(atPath: markerURL.path),
                          try String(contentsOf: markerURL, encoding: .utf8) == token else {
                        throw ContainerArtifactError.invalidManifest(
                            "created entry recovery marker is invalid: \(entry.path)")
                    }
                    if itemExistsWithoutFollowing(target) { try fm.removeItem(at: target) }
                } else {
                    guard entry.marker == nil, entry.token == nil else {
                        throw ContainerArtifactError.invalidManifest(
                            "replacement entries must not contain a recovery marker: \(entry.path)")
                    }
                    guard let backup = entry.backup else {
                        throw ContainerArtifactError.invalidManifest(
                            "replacement entry has no backup: \(entry.path)")
                    }
                    let backupURL = URL(fileURLWithPath: backup)
                        .standardizedFileURL.resolvingSymlinksInPath()
                    guard let trustedBackupRoot,
                          isContained(backupURL, by: trustedBackupRoot) else {
                        throw SafeRelativePathError.escapesRoot(backup)
                    }
                    guard fm.fileExists(atPath: backupURL.path) else {
                        throw CocoaError(.fileNoSuchFile)
                    }
                    let staged = target.deletingLastPathComponent()
                        .appendingPathComponent(".sipi-restore-" + UUID().uuidString)
                    try fm.createDirectory(
                        at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.copyItem(at: backupURL, to: staged)
                    do {
                        // `replaceItemAt` resolves the original path, so a leaf the
                        // app swapped for a symlink makes it fail and strands the
                        // backup. Unlink the link itself first — never its
                        // destination — and move the restored copy into place.
                        if isSymbolicLink(target) {
                            try fm.removeItem(at: target)
                            try fm.moveItem(at: staged, to: target)
                        } else if itemExistsWithoutFollowing(target) {
                            _ = try fm.replaceItemAt(target, withItemAt: staged)
                        } else {
                            try fm.moveItem(at: staged, to: target)
                        }
                    } catch {
                        try? fm.removeItem(at: staged)
                        throw error
                    }
                }
                removeEmptyDirectories(entry.createdDirectories ?? [], root: root)
            } catch {
                failures.append("\(entry.path): \(error)")
            }
        }
        return failures
    }

    private static func isContained(_ candidate: URL, by root: URL) -> Bool {
        candidate.path == root.path || candidate.path.hasPrefix(root.path + "/")
    }

    private static func rejectSymlinksAndSpecialFiles(in source: URL, isDirectory: Bool) throws {
        let fm = FileManager.default
        let sourceAttributes = try fm.attributesOfItem(atPath: source.path)
        let sourceType = sourceAttributes[.type] as? FileAttributeType
        if sourceType == .typeSymbolicLink {
            throw SafeRelativePathError.symbolicLink(source.path)
        }
        guard sourceType == .typeRegular || sourceType == .typeDirectory else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        guard isDirectory, let enumerator = fm.enumerator(atPath: source.path) else { return }
        for case let relative as String in enumerator {
            let item = source.appendingPathComponent(relative)
            let attributes = try fm.attributesOfItem(atPath: item.path)
            let type = attributes[.type] as? FileAttributeType
            if type == .typeSymbolicLink {
                throw SafeRelativePathError.symbolicLink(item.path)
            }
            guard type == .typeRegular || type == .typeDirectory else {
                throw CocoaError(.fileReadUnsupportedScheme)
            }
        }
    }

    private static func removeEmptyDirectories(_ paths: [String], root: URL) {
        let fm = FileManager.default
        for path in paths.reversed() {
            guard let directory = try? SafeRelativePath.resolve(root: root, relative: path),
                  let contents = try? fm.contentsOfDirectory(atPath: directory.path),
                  contents.isEmpty else { continue }
            try? fm.removeItem(at: directory)
        }
    }

    /// Cleanup must be able to unlink a leaf that the app replaced with a
    /// symlink, while still rejecting symlinks in every parent component.
    private static func resolveMutationTarget(root: URL, relative: String) throws -> URL {
        let normalized = try SafeRelativePath.normalize(relative)
        let components = normalized.split(separator: "/").map(String.init)
        guard let leaf = components.last else { throw SafeRelativePathError.empty }
        let parent: URL
        if components.count == 1 {
            parent = root.standardizedFileURL.resolvingSymlinksInPath()
        } else {
            parent = try SafeRelativePath.resolve(
                root: root,
                relative: components.dropLast().joined(separator: "/"))
        }
        return parent.appendingPathComponent(leaf).standardizedFileURL
    }

    private static func itemExistsWithoutFollowing(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    /// True for a symlink at `url` itself; `attributesOfItem` does not follow it.
    private static func isSymbolicLink(_ url: URL) -> Bool {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.type] as? FileAttributeType == .typeSymbolicLink
    }
}
