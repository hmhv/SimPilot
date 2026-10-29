import SimCore
import SimShell
import XCTest
@testable import sipi

final class DataArtifactCommandTests: XCTestCase {
    func testContainerPutParsesDataAndGroupTargets() throws {
        _ = try Sipi.ContainerCommand.Put.parse([
            "device", "com.example.app", "fixture.json",
            "--destination", "Documents/Inbox/fixture.json",
            "--manifest", "run/fixture-manifest.json"
        ])
        _ = try Sipi.ContainerCommand.Cleanup.parse([
            "device", "com.example.app", "run/fixture-manifest.json",
            "--group", "group.com.example.shared"
        ])
        _ = try Sipi.ContainerCommand.Put.parse([
            "device", "com.example.app", "fixture.json",
            "--group", "group.com.example.shared",
            "--destination", "state/fixture.json"
        ])
    }

    func testInspectionAndEvidenceCommandsParse() throws {
        _ = try Sipi.ContainerCommand.Inspect.parse([
            "device", "com.example.app", "db.sqlite",
            "--format", "sqlite", "--query", "select * from items"
        ])
        _ = try Sipi.FilesAppCommand.Put.parse([
            "device", "fixture.json", "--destination", "Imports/fixture.json"
        ])
        _ = try Sipi.FilesAppCommand.Cleanup.parse([
            "device", "files-app-manifest.json", "--storage", "/tmp/storage"
        ])
        _ = try Sipi.XCAppDataCommand.Create.parse([
            "device", "com.example.app", "fixture.xcappdata"
        ])
        _ = try Sipi.CrashEvidenceCommand.parse([
            "device", "com.example.app", "crashes",
            "--since", "2026-08-19T12:00:00+09:00"
        ])
    }

    func testCleanupManifestRestoresOneSelectedRootAtATime() throws {
        let work = try temporaryDirectory()
        let firstRoot = try temporaryDirectory()
        let secondRoot = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: work)
            try? FileManager.default.removeItem(at: firstRoot)
            try? FileManager.default.removeItem(at: secondRoot)
        }
        let manifestPath = work.appendingPathComponent("fixture-manifest.json").path
        let backups = work.appendingPathComponent("fixture-manifest-backups")
        let source = work.appendingPathComponent("fixture")
        try Data("fixture".utf8).write(to: source)
        for root in [firstRoot, secondRoot] {
            try Data("original".utf8).write(to: root.appendingPathComponent("state"))
        }
        var manifest = FileMutationManifest()
        for root in [firstRoot, secondRoot] {
            try ContainerArtifacts.put(
                source: source,
                root: root,
                destination: "state",
                backupDirectory: backups,
                manifest: &manifest,
                persistManifest: { try DataArtifactCLI.saveManifest($0, path: manifestPath) }
            )
        }

        let first = try DataArtifactCLI.cleanupManifest(
            path: manifestPath, selectedRoot: firstRoot)
        XCTAssertEqual(first.cleaned, 1)
        XCTAssertEqual(first.remaining, 1)
        XCTAssertEqual(
            try String(contentsOf: firstRoot.appendingPathComponent("state"), encoding: .utf8),
            "original")
        XCTAssertEqual(
            try String(contentsOf: secondRoot.appendingPathComponent("state"), encoding: .utf8),
            "fixture")

        let second = try DataArtifactCLI.cleanupManifest(
            path: manifestPath, selectedRoot: secondRoot)
        XCTAssertEqual(second.cleaned, 1)
        XCTAssertEqual(second.remaining, 0)
        XCTAssertEqual(
            try String(contentsOf: secondRoot.appendingPathComponent("state"), encoding: .utf8),
            "original")
    }

    func testCleanupManifestCannotDeleteUntrustedMarkerPath() throws {
        let work = try temporaryDirectory()
        let root = try temporaryDirectory()
        let victim = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: work)
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: victim)
        }
        let target = root.appendingPathComponent("state")
        try Data("original".utf8).write(to: target)
        let source = work.appendingPathComponent("fixture")
        try Data("fixture".utf8).write(to: source)
        let manifestPath = work.appendingPathComponent("manifest.json").path
        var manifest = FileMutationManifest()
        try ContainerArtifacts.put(
            source: source,
            root: root,
            destination: "state",
            backupDirectory: work.appendingPathComponent("backups"),
            manifest: &manifest
        )
        manifest.entries[0].marker = victim.path
        try DataArtifactCLI.saveManifest(manifest, path: manifestPath)

        XCTAssertThrowsError(try DataArtifactCLI.cleanupManifest(
            path: manifestPath, selectedRoot: root))
        XCTAssertTrue(FileManager.default.fileExists(atPath: victim.path))
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "fixture")
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
