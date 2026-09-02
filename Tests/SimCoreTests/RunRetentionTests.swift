// RunRetentionTests.swift
//
// Locks `keep-runs` pruning: only harness-named directories are candidates,
// the newest N survive, zero disables rather than deletes everything.

import XCTest
@testable import SimCore

final class RunRetentionTests: XCTestCase {
    private let names = [
        "2026-09-01_100000_iphone17_abc1234",
        "2026-09-02_090000_iphone17_abc1234",
        "2026-08-30_235959_ipadpro_nogit",
        "notes",
        "2026-09-02_120000_iphone17_def5678",
        ".DS_Store"
    ]

    func testKeepsTheNewestAndReturnsTheRestOldestFirst() {
        XCTAssertEqual(
            RunRetention.directoriesToPrune(names: names, keep: 2),
            ["2026-08-30_235959_ipadpro_nogit", "2026-09-01_100000_iphone17_abc1234"])
    }

    func testNothingToPruneWhenWithinBudget() {
        XCTAssertEqual(RunRetention.directoriesToPrune(names: names, keep: 4), [])
        XCTAssertEqual(RunRetention.directoriesToPrune(names: names, keep: 10), [])
    }

    func testZeroOrNegativeDisablesPruning() {
        XCTAssertEqual(RunRetention.directoriesToPrune(names: names, keep: 0), [])
        XCTAssertEqual(RunRetention.directoriesToPrune(names: names, keep: -1), [])
    }

    func testForeignDirectoriesAreNeverCandidates() {
        XCTAssertFalse(RunRetention.isHarnessRunName("notes"))
        XCTAssertFalse(RunRetention.isHarnessRunName("2026-09-02-not-a-run"))
        XCTAssertTrue(RunRetention.isHarnessRunName("2026-09-02_120000_x"))
        XCTAssertEqual(RunRetention.directoriesToPrune(names: ["notes", "a", "b"], keep: 1), [])
    }

    // MARK: - Completed-run detection

    private func makeRun(_ name: String, runJSON: String?) throws -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sipi-retention-\(UUID().uuidString)", isDirectory: true)
        let dir = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let runJSON {
            try runJSON.write(to: dir.appendingPathComponent("run.json"), atomically: true, encoding: .utf8)
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return dir.path
    }

    func testOnlyARunWithAFinishedTimestampIsCompleted() throws {
        XCTAssertTrue(RunRetention.isCompletedRun(at: try makeRun(
            "2026-09-01_100000_a", runJSON: #"{"started":"s","finished":"2026-09-01T10:00:05Z","tests":[]}"#)))
        // In progress: the harness writes run.json without `finished` at start.
        XCTAssertFalse(RunRetention.isCompletedRun(at: try makeRun(
            "2026-09-01_100000_b", runJSON: #"{"started":"s","tests":[]}"#)))
        XCTAssertFalse(RunRetention.isCompletedRun(at: try makeRun(
            "2026-09-01_100000_c", runJSON: #"{"started":"s","finished":"","tests":[]}"#)))
        // A stamped folder a person parked under runs/, and unreadable JSON.
        XCTAssertFalse(RunRetention.isCompletedRun(at: try makeRun("2026-09-01_100000_backup", runJSON: nil)))
        XCTAssertFalse(RunRetention.isCompletedRun(at: try makeRun("2026-09-01_100000_d", runJSON: "not json")))
        XCTAssertFalse(RunRetention.isCompletedRun(at: "/nonexistent/path"))
    }
}
