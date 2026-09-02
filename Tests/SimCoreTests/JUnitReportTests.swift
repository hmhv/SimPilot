// JUnitReportTests.swift
//
// Locks the JUnit rendering of a run directory: counts, one testcase per
// test, the first failed step as <failure> with its screenshot, skipped tests,
// XML escaping, and the run properties CI dashboards key on.

import XCTest
@testable import SimCore

final class JUnitReportTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sipi-junit-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    private func write(_ object: [String: Any], to relative: String) throws {
        let url = tempDir.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: object).write(to: url)
    }

    func testRendersSuiteCasesFailureAndSkipped() throws {
        try write([
            "started": "2026-09-02T10:00:00+09:00",
            "device": "UDID-1",
            "device-name": "iPhone 17",
            "device-runtime": "iOS 27.0",
            "suite": "smoke & regression",
            "commit": "abc1234",
            "tests": [
                ["id": "login-flow", "passed": true, "duration": 3.2],
                ["id": "settings-toggle", "passed": false, "duration": 1.5],
                ["id": "checkout", "passed": true, "skipped": true, "duration": 0],
                ["id": "profile", "passed": true, "review": true, "duration": 2]
            ],
            "summary": ["total": 4, "passed": 3, "failed": 1]
        ], to: "run.json")
        try write([
            "id": "settings-toggle", "passed": false, "duration": 1.5,
            "steps": [
                ["passed": true, "action": "tap id settings"],
                ["passed": false, "action": "tap label \"Dark <Mode>\"", "failure-type": "verify",
                 "screenshot": "step-002.png",
                 "verify": [["check": "contains: Dark", "found": true], ["check": "absent: Light", "found": false]]]
            ]
        ], to: "settings-toggle/result.json")

        let xml = try JUnitReport.xml(runDir: tempDir.path)

        XCTAssertTrue(xml.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<testsuite name=\"smoke &amp; regression\" tests=\"4\" failures=\"1\" errors=\"0\" skipped=\"1\" time=\"6.700\" timestamp=\"2026-09-02T10:00:00+09:00\" hostname=\"iPhone 17\">"), xml)
        XCTAssertTrue(xml.contains("<property name=\"device\" value=\"iPhone 17\"/>"))
        XCTAssertTrue(xml.contains("<property name=\"runtime\" value=\"iOS 27.0\"/>"))
        XCTAssertTrue(xml.contains("<property name=\"udid\" value=\"UDID-1\"/>"))
        XCTAssertTrue(xml.contains("<property name=\"commit\" value=\"abc1234\"/>"))
        XCTAssertTrue(xml.contains("<testcase name=\"login-flow\" classname=\"smoke &amp; regression\" time=\"3.200\"/>"))
        XCTAssertTrue(xml.contains(
            "<failure message=\"step 2 (tap label &quot;Dark &lt;Mode&gt;&quot;): verify — absent: Light\" type=\"verify\">"
            + "unmet: absent: Light\nscreenshot: settings-toggle/step-002.png</failure>"), xml)
        XCTAssertTrue(xml.contains("<testcase name=\"checkout\" classname=\"smoke &amp; regression\" time=\"0.000\">\n    <skipped/>\n  </testcase>"))
        XCTAssertTrue(xml.contains("<system-out>flagged for review</system-out>"))
        XCTAssertTrue(xml.hasSuffix("</testsuite>\n"))
    }

    func testSingleTestRunUsesRunIDAsSuiteName() throws {
        try write([
            "started": "2026-09-02T10:00:00+09:00", "device": "U",
            "tests": [["id": "only", "passed": true, "duration": 1]],
            "summary": ["total": 1, "passed": 1, "failed": 0]
        ], to: "run.json")
        let xml = try JUnitReport.xml(runDir: tempDir.path)
        let runID = tempDir.lastPathComponent
        XCTAssertTrue(xml.contains("<testsuite name=\"\(runID)\""))
        XCTAssertTrue(xml.contains("classname=\"\(runID)\""))
    }

    func testFailureWithoutResultJSONAndCleanupErrorAreDescribed() throws {
        try write([
            "started": "s", "device": "U",
            "tests": [["id": "gone", "passed": false, "duration": 1], ["id": "dirty", "passed": false, "duration": 1]],
            "summary": ["total": 2, "passed": 0, "failed": 2]
        ], to: "run.json")
        try write(["id": "dirty", "passed": false, "duration": 1, "steps": [["passed": true]],
                   "cleanup-error": "could not restore Documents/a.txt"], to: "dirty/result.json")
        let xml = try JUnitReport.xml(runDir: tempDir.path)
        XCTAssertTrue(xml.contains("<failure message=\"result.json missing\" type=\"action\">gone/result.json was not written</failure>"))
        XCTAssertTrue(xml.contains("<failure message=\"fixture restoration failed\" type=\"cleanup\">could not restore Documents/a.txt</failure>"))
    }

    func testActionFailureCarriesTheNoteInTheMessage() {
        let failure = JUnitReport.describeFailure(testID: "t", result: [
            "steps": [["passed": false, "action": "tap id x", "failure-type": "action",
                       "note": "Multiple (3) accessibility elements matched"]]
        ])
        XCTAssertEqual(failure.type, "action")
        XCTAssertEqual(failure.message, "step 1 (tap id x): action — Multiple (3) accessibility elements matched")
        XCTAssertEqual(failure.detail, "note: Multiple (3) accessibility elements matched")
    }

    func testMissingRunJSONThrows() {
        XCTAssertThrowsError(try JUnitReport.xml(runDir: tempDir.path + "/nope"))
    }

    func testEscapeDropsControlCharactersButKeepsNewlines() {
        XCTAssertEqual(JUnitReport.escape("a<b>&\"c'\n\u{01}d"), "a&lt;b&gt;&amp;&quot;c&apos;\nd")
    }

    func testWriteProducesJunitXMLInRunDir() throws {
        try write(["started": "s", "device": "U", "tests": [], "summary": ["total": 0, "passed": 0, "failed": 0]], to: "run.json")
        let path = try JUnitReport.write(runDir: tempDir.path)
        XCTAssertEqual(path, tempDir.path + "/junit.xml")
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }
}
