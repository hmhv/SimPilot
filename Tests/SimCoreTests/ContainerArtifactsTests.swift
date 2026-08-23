import Foundation
import XCTest
@testable import SimCore

final class ContainerArtifactsTests: XCTestCase {
    func testArtifactTimeParsesISO8601WithAndWithoutFractionalSeconds() {
        XCTAssertNotNil(ArtifactTime.parseISO8601("2026-08-19T12:34:56+09:00"))
        XCTAssertNotNil(ArtifactTime.parseISO8601("2026-08-19T12:34:56.789+09:00"))
        XCTAssertNil(ArtifactTime.parseISO8601("2026-08-19T12:34:56"))
    }

    func testRelativePathRejectsTraversalAndAbsolutePaths() throws {
        XCTAssertEqual(try SafeRelativePath.normalize("Documents//Inbox/./a.json"), "Documents/Inbox/a.json")
        XCTAssertThrowsError(try SafeRelativePath.normalize("../outside"))
        XCTAssertThrowsError(try SafeRelativePath.normalize("/tmp/outside"))
        XCTAssertThrowsError(try SafeRelativePath.normalize("."))
    }

    func testResolveRejectsExistingSymlink() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("link"),
            withDestinationURL: outside
        )
        XCTAssertThrowsError(try SafeRelativePath.resolve(root: root, relative: "link/escape.txt"))
    }

    func testSnapshotDiffAndReversiblePut() throws {
        let root = try makeTemporaryDirectory()
        let work = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: work)
        }
        let existing = root.appendingPathComponent("state.json")
        try Data("old".utf8).write(to: existing)
        let before = try ContainerArtifacts.snapshot(root: root)

        let source = work.appendingPathComponent("new.json")
        try Data("new".utf8).write(to: source)
        var manifest = FileMutationManifest()
        try ContainerArtifacts.put(
            source: source,
            root: root,
            destination: "state.json",
            backupDirectory: work.appendingPathComponent("backups"),
            manifest: &manifest
        )
        let after = try ContainerArtifacts.snapshot(root: root)
        XCTAssertEqual(before.files.count, 1)
        XCTAssertEqual(after.files.count, 1)
        XCTAssertNotEqual(before.files.first?.sha256, after.files.first?.sha256)
        let diff = try ContainerArtifacts.diff(before: before, after: after)
        XCTAssertEqual(diff.changed.map(\.path), ["state.json"])
        XCTAssertTrue(ContainerArtifacts.cleanup(
            manifest,
            allowedRoots: [root],
            allowedBackupRoot: work.appendingPathComponent("backups")
        ).isEmpty)
        XCTAssertEqual(String(data: try Data(contentsOf: existing), encoding: .utf8), "old")
    }

    func testCleanupRejectsManifestRootOutsideTrustedDirectory() throws {
        let trusted = try makeTemporaryDirectory()
        let outside = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: trusted)
            try? FileManager.default.removeItem(at: outside)
        }
        let victim = outside.appendingPathComponent("victim.txt")
        try Data("keep".utf8).write(to: victim)
        let manifest = FileMutationManifest(entries: [
            FileMutationEntry(root: outside.path, path: "victim.txt", backup: nil, created: true)
        ])

        XCTAssertFalse(ContainerArtifacts.cleanup(manifest, allowedRoots: [trusted]).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: victim.path))
    }

    func testCleanupDoesNotDeleteReplacementWhenBackupIsMissing() throws {
        let root = try makeTemporaryDirectory()
        let backups = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: backups)
        }
        let target = root.appendingPathComponent("state.json")
        try Data("fixture".utf8).write(to: target)
        let manifest = FileMutationManifest(entries: [FileMutationEntry(
            root: root.path,
            path: "state.json",
            backup: backups.appendingPathComponent("missing").path,
            created: false
        )])

        XCTAssertFalse(ContainerArtifacts.cleanup(
            manifest, allowedRoots: [root], allowedBackupRoot: backups).isEmpty)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "fixture")
    }

    func testCreatedFixtureRequiresItsRecoveryMarkerBeforeDeletion() throws {
        let root = try makeTemporaryDirectory()
        let work = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: work)
        }
        let source = work.appendingPathComponent("fixture")
        try Data("fixture".utf8).write(to: source)
        let backups = work.appendingPathComponent("backups")
        var manifest = FileMutationManifest()
        let target = try ContainerArtifacts.put(
            source: source,
            root: root,
            destination: "Created/Nested/new-file",
            backupDirectory: backups,
            manifest: &manifest
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))

        var tampered = manifest
        tampered.entries[0].token = "wrong"
        XCTAssertFalse(ContainerArtifacts.cleanup(
            tampered, allowedRoots: [root], allowedBackupRoot: backups).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))

        XCTAssertTrue(ContainerArtifacts.cleanup(
            manifest, allowedRoots: [root], allowedBackupRoot: backups).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Created").path))
    }

    func testPutRejectsSymlinkSources() throws {
        let root = try makeTemporaryDirectory()
        let work = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: work)
        }
        let link = work.appendingPathComponent("fixture-link")
        try FileManager.default.createSymbolicLink(
            at: link, withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
        var manifest = FileMutationManifest()
        XCTAssertThrowsError(try ContainerArtifacts.put(
            source: link,
            root: root,
            destination: "Documents/fixture",
            backupDirectory: work.appendingPathComponent("backups"),
            manifest: &manifest
        ))
        XCTAssertTrue(manifest.entries.isEmpty)
    }

    func testCleanupUnlinksLeafSymlinkCreatedByApp() throws {
        let root = try makeTemporaryDirectory()
        let work = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: work)
        }
        let source = work.appendingPathComponent("fixture")
        try Data("fixture".utf8).write(to: source)
        let backups = work.appendingPathComponent("backups")
        var manifest = FileMutationManifest()
        let target = try ContainerArtifacts.put(
            source: source,
            root: root,
            destination: "Documents/state",
            backupDirectory: backups,
            manifest: &manifest
        )
        try FileManager.default.removeItem(at: target)
        try FileManager.default.createSymbolicLink(
            at: target, withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))

        XCTAssertTrue(ContainerArtifacts.cleanup(
            manifest, allowedRoots: [root], allowedBackupRoot: backups).isEmpty)
        XCTAssertThrowsError(try FileManager.default.attributesOfItem(atPath: target.path))
    }

    func testCleanupNeverFollowsALeafSymlinkOutOfTheRoot() throws {
        let root = try makeTemporaryDirectory()
        let work = try makeTemporaryDirectory()
        let outside = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: work)
            try? FileManager.default.removeItem(at: outside)
        }
        let secret = outside.appendingPathComponent("secret")
        let source = work.appendingPathComponent("fixture")
        try Data("fixture".utf8).write(to: source)
        let backups = work.appendingPathComponent("backups")

        // A `created` entry whose leaf the app swapped for a symlink out of the
        // container: cleanup must unlink the link, never touch its destination.
        try Data("original".utf8).write(to: secret)
        var created = FileMutationManifest()
        let createdTarget = try ContainerArtifacts.put(
            source: source, root: root, destination: "Documents/created",
            backupDirectory: backups, manifest: &created)
        try FileManager.default.removeItem(at: createdTarget)
        try FileManager.default.createSymbolicLink(at: createdTarget, withDestinationURL: secret)
        XCTAssertTrue(ContainerArtifacts.cleanup(
            created, allowedRoots: [root], allowedBackupRoot: backups).isEmpty)
        XCTAssertThrowsError(try FileManager.default.attributesOfItem(atPath: createdTarget.path))
        XCTAssertEqual(try String(contentsOf: secret, encoding: .utf8), "original")

        // Same swap on a `replacement` entry: restoring the backup must not
        // write through the link either.
        try Data("replaced-target".utf8).write(to: root.appendingPathComponent("existing"))
        var replaced = FileMutationManifest()
        let replacedTarget = try ContainerArtifacts.put(
            source: source, root: root, destination: "existing",
            backupDirectory: backups, manifest: &replaced)
        XCTAssertEqual(replaced.entries.first?.created, false)
        try FileManager.default.removeItem(at: replacedTarget)
        try FileManager.default.createSymbolicLink(at: replacedTarget, withDestinationURL: secret)
        XCTAssertTrue(ContainerArtifacts.cleanup(
            replaced, allowedRoots: [root], allowedBackupRoot: backups).isEmpty)
        XCTAssertEqual(try String(contentsOf: secret, encoding: .utf8), "original")
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(
                atPath: replacedTarget.path)[.type] as? FileAttributeType,
            .typeRegular,
            "the link must be unlinked and the backup restored in its place"
        )
        XCTAssertEqual(
            try String(contentsOf: replacedTarget, encoding: .utf8), "replaced-target")
    }

    func testDirectoryFixtureRestoresOriginalDirectory() throws {
        let root = try makeTemporaryDirectory()
        let work = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: work)
        }
        let target = root.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("original".utf8).write(to: target.appendingPathComponent("old.txt"))
        let source = work.appendingPathComponent("fixture", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: source.appendingPathComponent("new.txt"))
        let backups = work.appendingPathComponent("backups")
        var manifest = FileMutationManifest()

        try ContainerArtifacts.put(
            source: source,
            root: root,
            destination: "Documents",
            backupDirectory: backups,
            manifest: &manifest
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("new.txt").path))
        XCTAssertTrue(ContainerArtifacts.cleanup(
            manifest, allowedRoots: [root], allowedBackupRoot: backups).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("old.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("new.txt").path))
    }

    func testPutFailureRestoresOriginalAndPersistsRecoveryBeforeMutation() throws {
        let root = try makeTemporaryDirectory()
        let work = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: work)
        }
        let target = root.appendingPathComponent("state.json")
        try Data("original".utf8).write(to: target)
        let source = work.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let unreadable = source.appendingPathComponent("unreadable")
        try Data("blocked".utf8).write(to: unreadable)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: unreadable.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: unreadable.path) }
        var manifest = FileMutationManifest()
        var persistedCounts: [Int] = []

        XCTAssertThrowsError(try ContainerArtifacts.put(
            source: source,
            root: root,
            destination: "state.json",
            backupDirectory: work.appendingPathComponent("backups"),
            manifest: &manifest,
            persistManifest: { persistedCounts.append($0.entries.count) }
        ))
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "original")
        XCTAssertTrue(manifest.entries.isEmpty)
        XCTAssertEqual(persistedCounts, [1, 0])
    }

    func testDiffToleratesDuplicatePathsInExternalSnapshots() throws {
        let first = ContainerFileRecord(path: "a", size: 1, sha256: "first")
        let last = ContainerFileRecord(path: "a", size: 2, sha256: "last")
        let before = ContainerSnapshot(root: "/tmp", files: [first, last])
        let after = ContainerSnapshot(root: "/tmp", files: [last])
        XCTAssertTrue(try ContainerArtifacts.diff(before: before, after: after).changed.isEmpty)
    }

    func testDiffRejectsDifferentContainerRoots() {
        XCTAssertThrowsError(try ContainerArtifacts.diff(
            before: ContainerSnapshot(root: "/one", files: []),
            after: ContainerSnapshot(root: "/two", files: [])
        ))
    }

    func testDiffDoesNotReportUnreadableFilesAsRemoved() throws {
        let record = ContainerFileRecord(path: "live.sqlite-wal", size: 1, sha256: "hash")
        let before = ContainerSnapshot(root: "/same", files: [record])
        let after = ContainerSnapshot(
            root: "/same",
            files: [],
            errors: [ContainerSnapshotError(path: record.path, error: "busy")]
        )
        let diff = try ContainerArtifacts.diff(before: before, after: after)
        XCTAssertTrue(diff.removed.isEmpty)
        XCTAssertEqual(diff.skipped?.map(\.path), [record.path])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
