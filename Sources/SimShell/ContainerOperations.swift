// ContainerOperations.swift
//
// Operations simctl does not provide itself: safe copying beneath a resolved
// app container, Files.app storage discovery, persistent-file inspection,
// xcappdata creation/validation, and focused crash evidence extraction.

import CoreFoundation
import Foundation
import SimCore

public enum ContainerKind: Equatable, Sendable {
    case data
    case group(String)

    public var simctlName: String {
        switch self {
        case .data: return "data"
        case .group(let identifier): return identifier
        }
    }
}

public struct FileInspection: Codable, Equatable, Sendable {
    public var exists: Bool
    public var size: UInt64?
    public var sha256: String?
    public var value: String?

    public init(exists: Bool, size: UInt64? = nil, sha256: String? = nil, value: String? = nil) {
        self.exists = exists
        self.size = size
        self.sha256 = sha256
        self.value = value
    }
}

public enum ContainerOperationError: Error, CustomStringConvertible {
    case notDirectory(String)
    case ambiguousFileProviderStorage([String])
    case noFileProviderStorage
    case unsupportedFormat(String)
    case invalidXCAppData(String)
    case sqliteFailed(String)
    case destinationExists(String)
    case notUTF8Text(String)

    public var description: String {
        switch self {
        case .notDirectory(let path): return "container root is not a directory: \(path)"
        case .ambiguousFileProviderStorage(let paths):
            return "multiple File Provider Storage roots found; select one explicitly: \(paths.joined(separator: ", "))"
        case .noFileProviderStorage: return "no File Provider Storage root was found for this simulator"
        case .unsupportedFormat(let value): return "unsupported inspection format: \(value)"
        case .invalidXCAppData(let value): return "invalid xcappdata package: \(value)"
        case .sqliteFailed(let value): return "SQLite query failed: \(value)"
        case .destinationExists(let path): return "destination already exists: \(path)"
        case .notUTF8Text(let path):
            return "file is not valid UTF-8 text; use format=metadata or sha256 instead: \(path)"
        }
    }
}

public enum SimulatorStorage {
    public static var devicesRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/CoreSimulator/Devices", isDirectory: true)
    }

    public static func deviceRoot(udid: String) throws -> URL {
        guard !udid.isEmpty, !udid.contains("/"), !udid.contains("..") else {
            throw SafeRelativePathError.traversal(udid)
        }
        return devicesRoot.appendingPathComponent(udid, isDirectory: true)
    }
}

public enum ContainerOperations {
    public static func root(udid: String, bundleID: String, kind: ContainerKind) throws -> URL {
        let path = try SimShell.appContainerPath(
            udid: udid,
            bundleID: bundleID,
            container: kind.simctlName
        )
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ContainerOperationError.notDirectory(path)
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    public static func list(root: URL, relative: String? = nil) throws -> [String] {
        let base = try relative.map { try SafeRelativePath.resolve(root: root, relative: $0) } ?? root
        let fm = FileManager.default
        let items = try fm.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        )
        let prefix = root.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        return try items.map { item in
            let values = try item.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values.isSymbolicLink == true { throw SafeRelativePathError.symbolicLink(item.path) }
            let canonicalItem = item.standardizedFileURL.resolvingSymlinksInPath()
            guard canonicalItem.path.hasPrefix(prefix) else {
                throw SafeRelativePathError.escapesRoot(canonicalItem.path)
            }
            return String(canonicalItem.path.dropFirst(prefix.count))
        }.sorted()
    }

    public static func pull(root: URL, relative: String, destination: URL) throws {
        let source = try SafeRelativePath.resolve(root: root, relative: relative)
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { throw CocoaError(.fileNoSuchFile) }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path) {
            throw ContainerOperationError.destinationExists(destination.path)
        }
        try fm.copyItem(at: source, to: destination)
    }

    public static func inspect(
        root: URL,
        relative: String,
        format: String = "metadata",
        keyPath: String? = nil,
        sqliteQuery: String? = nil,
        includeHash: Bool = true
    ) throws -> FileInspection {
        let url = try SafeRelativePath.resolve(root: root, relative: relative)
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return FileInspection(exists: false) }
        let attrs = try fm.attributesOfItem(atPath: url.path)
        guard attrs[.type] as? FileAttributeType == .typeRegular else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        let size = (attrs[.size] as? NSNumber)?.uint64Value
        let hash = includeHash ? try ContainerArtifacts.sha256(url) : nil
        switch format {
        case "metadata":
            return FileInspection(exists: true, size: size, sha256: hash)
        case "text":
            guard let text = String(data: try Data(contentsOf: url), encoding: .utf8) else {
                throw ContainerOperationError.notUTF8Text(relative)
            }
            return FileInspection(exists: true, size: size, sha256: hash, value: text)
        case "json":
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
            let selected = try keyPath.map { try value(at: $0, in: object) } ?? object
            return FileInspection(exists: true, size: size, sha256: hash, value: canonicalString(selected))
        case "plist":
            let object = try PropertyListSerialization.propertyList(
                from: Data(contentsOf: url), options: [], format: nil)
            let selected = try keyPath.map { try value(at: $0, in: object) } ?? object
            return FileInspection(exists: true, size: size, sha256: hash, value: canonicalString(selected))
        case "sqlite":
            guard let sqliteQuery, !sqliteQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ContainerOperationError.sqliteFailed("a non-empty query is required")
            }
            return FileInspection(
                exists: true, size: size, sha256: hash,
                value: try sqliteReadOnly(database: url, query: sqliteQuery)
            )
        default:
            throw ContainerOperationError.unsupportedFormat(format)
        }
    }

    /// Basic JSON/plist key path: optional leading `$`, dot-separated object
    /// keys, and numeric array indexes.
    public static func value(at rawPath: String, in root: Any) throws -> Any {
        var path = rawPath
        if path == "$" { return root }
        if path.hasPrefix("$.") { path.removeFirst(2) }
        var current: Any = root
        for component in path.split(separator: ".").map(String.init) {
            if let object = current as? [String: Any], let next = object[component] {
                current = next
            } else if let array = current as? [Any], let index = Int(component), array.indices.contains(index) {
                current = array[index]
            } else {
                throw CocoaError(.propertyListReadCorrupt)
            }
        }
        return current
    }

    public static func canonicalString(_ value: Any) -> String {
        if value is NSNull { return "null" }
        if let string = value as? String { return string }
        if let number = value as? NSNumber {
            return CFGetTypeID(number) == CFBooleanGetTypeID()
                ? (number.boolValue ? "true" : "false")
                : number.stringValue
        }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
            return String(decoding: data, as: UTF8.self)
        }
        return String(describing: value)
    }

    /// A `Data` box so stderr can be drained on its own queue. Reading one pipe
    /// to EOF before touching the other deadlocks as soon as the unread pipe
    /// fills its buffer, which a verbose SQLite error can do on its own.
    private final class DataBox: @unchecked Sendable {
        private var value = Data()
        func set(_ data: Data) { value = data }
        var contents: Data { value }
    }

    public static func sqliteReadOnly(database: URL, query: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "-safe", "-json", database.path, query]
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let errorBox = DataBox()
        let errorQueue = DispatchQueue(label: "com.simpilot.sqlite-stderr")
        errorQueue.async { errorBox.set(err.fileHandleForReading.readDataToEndOfFile()) }
        let output = out.fileHandleForReading.readDataToEndOfFile()
        errorQueue.sync {}
        let error = errorBox.contents
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ContainerOperationError.sqliteFailed(String(decoding: error, as: UTF8.self))
        }
        return String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum FileProviderStorage {
    /// Discover storage roots without hard-coding the random App Group UUID.
    /// The layout itself is an explicitly experimental Simulator workaround.
    public static func candidates(udid: String) throws -> [URL] {
        let shared = try SimulatorStorage.deviceRoot(udid: udid)
            .appendingPathComponent("data/Containers/Shared/AppGroup", isDirectory: true)
        let groups = (try? FileManager.default.contentsOfDirectory(
            at: shared,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        var roots: [URL] = []
        for group in groups {
            let values = try group.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { continue }
            let storage = group.appendingPathComponent("File Provider Storage", isDirectory: true)
            var isDirectory: ObjCBool = false
            let storageValues = try? storage.resourceValues(forKeys: [.isSymbolicLinkKey])
            if FileManager.default.fileExists(atPath: storage.path, isDirectory: &isDirectory),
               isDirectory.boolValue,
               storageValues?.isSymbolicLink != true {
                roots.append(storage)
            }
        }
        return roots.sorted { $0.path < $1.path }
    }

    public static func select(udid: String, explicitPath: String? = nil) throws -> URL {
        try select(candidates: candidates(udid: udid), explicitPath: explicitPath)
    }

    public static func select(candidates: [URL], explicitPath: String? = nil) throws -> URL {
        if let explicitPath {
            let explicit = URL(fileURLWithPath: explicitPath, isDirectory: true)
            let canonical = explicit.standardizedFileURL.resolvingSymlinksInPath().path
            guard let selected = candidates.first(where: {
                $0.standardizedFileURL.resolvingSymlinksInPath().path == canonical
            }) else {
                throw ContainerOperationError.noFileProviderStorage
            }
            return selected
        }
        if candidates.isEmpty { throw ContainerOperationError.noFileProviderStorage }
        if candidates.count > 1 {
            throw ContainerOperationError.ambiguousFileProviderStorage(candidates.map(\.path))
        }
        return candidates[0]
    }
}

public enum XCAppDataPackage {
    public static func create(dataContainer: URL, bundleID: String, output: URL) throws {
        guard !bundleID.isEmpty else { throw ContainerOperationError.invalidXCAppData("bundle ID is empty") }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dataContainer.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ContainerOperationError.notDirectory(dataContainer.path)
        }
        let fm = FileManager.default
        guard output.pathExtension == "xcappdata" else {
            throw ContainerOperationError.invalidXCAppData("output must have the .xcappdata extension")
        }
        if fm.fileExists(atPath: output.path) {
            throw ContainerOperationError.destinationExists(output.path)
        }
        let parent = output.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(".sipi-xcappdata-" + UUID().uuidString)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        try fm.copyItem(
            at: dataContainer,
            to: staging.appendingPathComponent("AppData", isDirectory: true))
        let metadata: [String: Any] = [
            "BundleIdentifier": bundleID,
            "Created": ArtifactTime.iso()
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0)
        try data.write(to: staging.appendingPathComponent("AppDataInfo.plist"), options: .atomic)
        try fm.moveItem(at: staging, to: output)
    }

    public static func validate(_ package: URL, expectedBundleID: String? = nil) throws -> String {
        let appData = package.appendingPathComponent("AppData", isDirectory: true)
        let info = package.appendingPathComponent("AppDataInfo.plist")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: appData.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              let data = FileManager.default.contents(atPath: info.path),
              let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let bundleID = plist["BundleIdentifier"] as? String,
              !bundleID.isEmpty else {
            throw ContainerOperationError.invalidXCAppData("missing AppData or AppDataInfo.plist BundleIdentifier")
        }
        if let expectedBundleID, bundleID != expectedBundleID {
            throw ContainerOperationError.invalidXCAppData(
                "bundle ID \(bundleID) does not match \(expectedBundleID)"
            )
        }
        return bundleID
    }
}

public struct CrashEvidenceRecord: Codable, Equatable, Sendable {
    public var source: String
    public var artifact: String
    public var modified: String
}

public enum CrashEvidence {
    public static func collect(
        udid: String,
        bundleID: String,
        since: Date,
        outputDirectory: URL
    ) throws -> [CrashEvidenceRecord] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let deviceData = try SimulatorStorage.deviceRoot(udid: udid).appendingPathComponent("data")
        let roots: [(url: URL, scope: String)] = [
            (deviceData.appendingPathComponent("Library/Logs/CrashReporter"), "simulator/CrashReporter"),
            (deviceData.appendingPathComponent("Library/Logs/DiagnosticReports"), "simulator/DiagnosticReports"),
            (home.appendingPathComponent("Library/Logs/DiagnosticReports"), "host/DiagnosticReports")
        ]
        let fm = FileManager.default
        try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        var records: [CrashEvidenceRecord] = []
        var usedNames = Set((try? fm.contentsOfDirectory(atPath: outputDirectory.path)) ?? [])
        for rootEntry in roots {
            guard let enumerator = fm.enumerator(
                at: rootEntry.url,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in enumerator {
                let values = try url.resourceValues(forKeys: [
                    .isRegularFileKey, .contentModificationDateKey, .isSymbolicLinkKey
                ])
                if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                guard values.isRegularFile == true,
                      ["ips", "crash"].contains(url.pathExtension.lowercased()),
                      let modified = values.contentModificationDate,
                      modified >= since,
                      let data = try? Data(contentsOf: url),
                      let text = String(data: data, encoding: .utf8),
                      reportHasExactBundleID(text, bundleID: bundleID) else { continue }
                var name = url.lastPathComponent
                if usedNames.contains(name) { name = UUID().uuidString + "-" + name }
                usedNames.insert(name)
                let destination = outputDirectory.appendingPathComponent(name)
                try fm.copyItem(at: url, to: destination)
                records.append(CrashEvidenceRecord(
                    source: rootEntry.scope + "/" + url.lastPathComponent,
                    artifact: name,
                    modified: ArtifactTime.iso(modified)
                ))
            }
        }
        return records.sorted { $0.modified < $1.modified }
    }

    static func reportHasExactBundleID(_ text: String, bundleID: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: bundleID)
        let patterns = [
            #""CFBundleIdentifier"\s*:\s*""# + escaped + #"""#,
            #"(?m)^\s*Identifier:\s*"# + escaped + #"\s*$"#,
            #""bundleID"\s*:\s*""# + escaped + #"""#
        ]
        return patterns.contains { pattern in
            text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }
}
