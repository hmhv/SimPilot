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

    func testContainerFileAssertionComparesEverySupportedValue() {
        let inspection = FileInspection(
            exists: true,
            size: 3,
            sha256: String(repeating: "a", count: 64),
            value: "1"
        )
        XCTAssertTrue(ContainerFileAssertion.matches(
            inspection,
            exists: true,
            size: 3,
            sha256: String(repeating: "A", count: 64),
            value: 1
        ))
        XCTAssertFalse(ContainerFileAssertion.matches(
            inspection, exists: true, size: 4, sha256: nil, value: nil))
        XCTAssertFalse(ContainerFileAssertion.matches(
            inspection, exists: true, size: nil, sha256: nil, value: true))
    }

    func testValueAssertionTrimsSurroundingWhitespace() throws {
        let trailingNewline = FileInspection(exists: true, size: 6, value: "hello\n")
        XCTAssertTrue(ContainerFileAssertion.matches(
            trailingNewline, exists: true, size: nil, sha256: nil, value: "hello"))
        XCTAssertTrue(ContainerFileAssertion.matches(
            FileInspection(exists: true, value: "  hello  "),
            exists: true, size: nil, sha256: nil, value: "hello"))
        // Trimming is only about surrounding whitespace, not about the value.
        XCTAssertFalse(ContainerFileAssertion.matches(
            trailingNewline, exists: true, size: nil, sha256: nil, value: "hell"))
        // A file whose text could not be decoded never satisfies a value.
        XCTAssertFalse(ContainerFileAssertion.matches(
            FileInspection(exists: true, size: 3, sha256: nil, value: nil),
            exists: true, size: nil, sha256: nil, value: ""))
    }

    func testHarnessJSONValuePreservesLargeIntegers() throws {
        let value = try JSONDecoder().decode(
            HarnessJSONValue.self, from: Data("1234567890123456789".utf8))
        XCTAssertEqual(
            ContainerOperations.canonicalString(value.foundationValue),
            "1234567890123456789"
        )
        let unsigned = try JSONDecoder().decode(
            HarnessJSONValue.self, from: Data("18446744073709551615".utf8))
        XCTAssertEqual(
            ContainerOperations.canonicalString(unsigned.foundationValue),
            "18446744073709551615"
        )
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

    func testLogSanitizerProducesStrictNDJSONAndDetectsEmptyCapture() throws {
        let banner = "Filtering the log data using \"subsystem == app\"\n\n"
        let event = #"{"eventMessage":"saved","timestamp":"2026-08-20T00:00:00+09:00"}"#
        let footer = #"{"count":1,"finished":1}"#
        let result = LogNDJSONSanitizer.sanitize(
            Data((banner + event + "\n" + footer + "\n").utf8))
        XCTAssertEqual(result.recordCount, 1)
        XCTAssertTrue(result.unexpectedLines.isEmpty)
        for line in String(decoding: result.data, as: UTF8.self).split(separator: "\n") {
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(line.utf8)))
        }

        let empty = LogNDJSONSanitizer.sanitize(Data((banner + #"{"count":0,"finished":1}"#).utf8))
        XCTAssertEqual(empty.recordCount, 0)
        XCTAssertTrue(empty.data.isEmpty)
    }

    func testEvidencePlanIncludesPerTestAppOverrides() {
        let bundleIDs = HarnessEvidence.bundleIDs(
            primary: "com.example.primary",
            testOverrides: ["com.example.secondary", "com.example.primary"])
        XCTAssertEqual(bundleIDs, ["com.example.primary", "com.example.secondary"])

        let predicate = HarnessEvidence.logPredicate(bundleIDs: bundleIDs) { bundleID in
            bundleID == "com.example.primary" ? "PrimaryApp" : "SecondaryApp"
        }
        XCTAssertTrue(predicate.contains(#"subsystem == "com.example.primary""#))
        XCTAssertTrue(predicate.contains(#"subsystem == "com.example.secondary""#))
        XCTAssertTrue(predicate.contains(#"process == "PrimaryApp""#))
        XCTAssertTrue(predicate.contains(#"process == "SecondaryApp""#))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
