import Foundation
import XCTest
@testable import SimShell

final class ContainerOperationsTests: XCTestCase {
    func testCanonicalStringDistinguishesNumbersFromBooleans() throws {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(#"{"zero":0,"one":1,"yes":true}"#.utf8)) as? [String: Any])
        XCTAssertEqual(ContainerOperations.canonicalString(try XCTUnwrap(object["zero"])), "0")
        XCTAssertEqual(ContainerOperations.canonicalString(try XCTUnwrap(object["one"])), "1")
        XCTAssertEqual(ContainerOperations.canonicalString(try XCTUnwrap(object["yes"])), "true")
    }

    func testFileProviderSelectionRejectsPathOutsideCandidates() throws {
        let candidate = URL(fileURLWithPath: "/tmp/allowed")
        XCTAssertThrowsError(try FileProviderStorage.select(
            candidates: [candidate], explicitPath: "/tmp/not-allowed"))
        XCTAssertEqual(
            try FileProviderStorage.select(candidates: [candidate], explicitPath: candidate.path),
            candidate
        )
    }

    func testListAndPullStayWithinRoot() throws {
        let root = try temporaryDirectory()
        let output = try temporaryDirectory().appendingPathComponent("copy.txt")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output.deletingLastPathComponent())
        }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Documents"), withIntermediateDirectories: true)
        try Data("value".utf8).write(to: root.appendingPathComponent("Documents/value.txt"))

        XCTAssertEqual(try ContainerOperations.list(root: root), ["Documents"])
        XCTAssertEqual(try ContainerOperations.list(root: root, relative: "Documents"), ["Documents/value.txt"])
        try ContainerOperations.pull(root: root, relative: "Documents/value.txt", destination: output)
        XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), "value")
        XCTAssertThrowsError(try ContainerOperations.pull(
            root: root, relative: "Documents/value.txt", destination: output))
        XCTAssertThrowsError(try ContainerOperations.pull(
            root: root, relative: "../outside", destination: output))
    }

    func testSQLiteInspectionUsesSafeMode() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = root.appendingPathComponent("test.sqlite")
        try runSQLite(database: database, query: "create table values_table(value text); insert into values_table values ('ok');")
        XCTAssertEqual(
            try ContainerOperations.sqliteReadOnly(
                database: database, query: "select value from values_table"),
            #"[{"value":"ok"}]"#
        )
        let marker = root.appendingPathComponent("written.txt")
        XCTAssertThrowsError(try ContainerOperations.sqliteReadOnly(
            database: database,
            query: "select writefile('\(marker.path)', 'unsafe')"
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testCrashReportBundleMatchingIsExact() {
        XCTAssertTrue(CrashEvidence.reportHasExactBundleID(
            #"{"bundleInfo":{"CFBundleIdentifier":"com.example.app"}}"#,
            bundleID: "com.example.app"))
        XCTAssertTrue(CrashEvidence.reportHasExactBundleID(
            "Identifier: com.example.app\n",
            bundleID: "com.example.app"))
        XCTAssertFalse(CrashEvidence.reportHasExactBundleID(
            #"{"note":"com.example.app","CFBundleIdentifier":"com.example.app.helper"}"#,
            bundleID: "com.example.app"))
    }

    func testJSONAndPlistInspection() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(#"{"user":{"loggedIn":true}}"#.utf8)
            .write(to: root.appendingPathComponent("state.json"))
        let json = try ContainerOperations.inspect(
            root: root, relative: "state.json", format: "json", keyPath: "$.user.loggedIn",
            includeHash: false)
        XCTAssertEqual(json.value, "true")
        XCTAssertNil(json.sha256)

        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["count": 3], format: .xml, options: 0)
        try plist.write(to: root.appendingPathComponent("defaults.plist"))
        let inspected = try ContainerOperations.inspect(
            root: root, relative: "defaults.plist", format: "plist", keyPath: "count")
        XCTAssertEqual(inspected.value, "3")
    }

    func testXCAppDataCreateAndValidate() throws {
        let data = try temporaryDirectory()
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("xcappdata")
        defer {
            try? FileManager.default.removeItem(at: data)
            try? FileManager.default.removeItem(at: output)
        }
        try Data("fixture".utf8).write(to: data.appendingPathComponent("state.txt"))
        try XCAppDataPackage.create(dataContainer: data, bundleID: "com.example.app", output: output)
        XCTAssertEqual(try XCAppDataPackage.validate(output), "com.example.app")
        XCTAssertThrowsError(try XCAppDataPackage.create(
            dataContainer: data, bundleID: "com.example.app", output: output))
        XCTAssertThrowsError(try XCAppDataPackage.validate(output, expectedBundleID: "wrong.bundle"))
    }

    func testTextInspectionKeepsRawValueAndRejectsBinary() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("hello\n".utf8).write(to: root.appendingPathComponent("text.txt"))
        try Data([0xff, 0xfe, 0x00]).write(to: root.appendingPathComponent("binary.bin"))

        // Inspection reports the file unmodified; only assertions trim.
        XCTAssertEqual(
            try ContainerOperations.inspect(root: root, relative: "text.txt", format: "text").value,
            "hello\n"
        )
        XCTAssertThrowsError(
            try ContainerOperations.inspect(root: root, relative: "binary.bin", format: "text")
        ) { error in
            guard case ContainerOperationError.notUTF8Text = error else {
                return XCTFail("expected notUTF8Text, got \(error)")
            }
        }
        // A binary file is still inspectable by metadata and hash.
        XCTAssertEqual(
            try ContainerOperations.inspect(root: root, relative: "binary.bin").size, 3)
    }

    func testListIncludesDotFiles() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("{}".utf8).write(
            to: root.appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist"))
        try Data("value".utf8).write(to: root.appendingPathComponent("visible.txt"))

        XCTAssertEqual(
            try ContainerOperations.list(root: root),
            [".com.apple.mobile_container_manager.metadata.plist", "visible.txt"]
        )
    }

    func testCrashSourceNamesTheReportDirectory() throws {
        let device = UUID().uuidString
        let deviceRoot = try SimulatorStorage.deviceRoot(udid: device)
        let output = try temporaryDirectory()
        let simulatorReports = deviceRoot.appendingPathComponent("data/Library/Logs/DiagnosticReports")
        defer {
            try? FileManager.default.removeItem(at: deviceRoot)
            try? FileManager.default.removeItem(at: output)
        }
        try FileManager.default.createDirectory(at: simulatorReports, withIntermediateDirectories: true)
        try Data(#"{"bundleID":"com.example.app"}"#.utf8).write(
            to: simulatorReports.appendingPathComponent("crash.ips"))

        let records = try CrashEvidence.collect(
            udid: device,
            bundleID: "com.example.app",
            since: Date().addingTimeInterval(-60),
            outputDirectory: output
        )
        XCTAssertEqual(records.map(\.source), ["simulator/DiagnosticReports/crash.ips"])
    }

    private func runSQLite(database: URL, query: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [database.path, query]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
