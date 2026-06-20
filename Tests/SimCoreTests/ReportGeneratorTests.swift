// ReportGeneratorTests.swift
//
// Locks the report generation that moved INTO the sipi binary (STAGE REPORT):
// the test-run and verify HTML reports formerly produced by the loose
// interpreter scripts now come from SimCore.ReportGenerator. These build a small
// fixture run/verify directory on disk and assert the generated HTML carries the
// expected structural markers, Base64-embedded PNG, and the verify thumbnail
// max-width:220px sizing fix.

import XCTest
import Foundation
@testable import SimCore

final class ReportGeneratorTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sipi-report-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    /// A minimal 1x1 PNG so the Base64 image-embedding path is exercised.
    private static let tinyPNGBase64 =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="

    private func writePNG(to url: URL) throws {
        let data = Data(base64Encoded: Self.tinyPNGBase64)!
        try data.write(to: url)
    }

    // MARK: - Test run report

    func testTestReportContainsExpectedMarkers() throws {
        // Build a small run dir: run.json + one test with a result.json + screenshot.
        let runDir = tempDir.appendingPathComponent("run", isDirectory: true)
        let testDir = runDir.appendingPathComponent("login-flow", isDirectory: true)
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

        let run: [String: Any] = [
            "started": "2026-06-19T10:00:00+09:00",
            "device": "90E3942F-1B58-474A-A9D6-916173D43661",
            "device-name": "iPhone 16",
            "device-runtime": "iOS 18.0",
            "suite": "Smoke Suite",
            "commit": "abc1234",
            "tests": [["id": "login-flow", "passed": true, "duration": 3.2]],
            "summary": ["total": 1, "passed": 1, "failed": 0]
        ]
        try Data(JSONSerialization.data(withJSONObject: run))
            .write(to: runDir.appendingPathComponent("run.json"))

        try writePNG(to: testDir.appendingPathComponent("step-001.png"))
        let result: [String: Any] = [
            "id": "login-flow",
            "passed": true,
            "duration": 3.2,
            "steps": [[
                "passed": true,
                "action": "tap Login",
                "note": "ok",
                "screenshot": "step-001.png",
                "duration": 1.1
            ]]
        ]
        try Data(JSONSerialization.data(withJSONObject: result))
            .write(to: testDir.appendingPathComponent("result.json"))

        let html = try ReportGenerator.testReportHTML(runDir: runDir.path)

        // Structural markers
        XCTAssertTrue(html.contains("<!DOCTYPE html>"), "expected an HTML document")
        XCTAssertTrue(html.contains("<title>Test Run: Smoke Suite</title>"), "expected suite name in title")
        XCTAssertTrue(html.contains("Smoke Suite"), "expected suite name in body")
        XCTAssertTrue(html.contains("iPhone 16"), "expected device name in meta")
        XCTAssertTrue(html.contains("badge-pass"), "expected a PASS badge for the passing test")
        XCTAssertTrue(html.contains("1 tests"), "expected the summary total")
        XCTAssertTrue(html.contains("login-flow"), "expected the test id")
        XCTAssertTrue(html.contains("openLightbox"), "expected the lightbox JS")

        // Base64 PNG embedding (no external image references)
        XCTAssertTrue(html.contains("data:image/png;base64,"),
                      "expected the screenshot to be embedded as a Base64 data URI")
    }

    func testWriteTestReportProducesFile() throws {
        let runDir = tempDir.appendingPathComponent("run2", isDirectory: true)
        try FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true)
        let run: [String: Any] = [
            "started": "2026-06-19T10:00:00+09:00",
            "device": "udid",
            "tests": [],
            "summary": ["total": 0, "passed": 0, "failed": 0]
        ]
        try Data(JSONSerialization.data(withJSONObject: run))
            .write(to: runDir.appendingPathComponent("run.json"))

        let outPath = try ReportGenerator.writeTestReport(runDir: runDir.path)
        XCTAssertEqual(outPath, runDir.path + "/report.html")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outPath),
                      "report.html should be written to the run dir")
    }

    func testTestReportMissingRunJSONThrows() {
        let missing = tempDir.appendingPathComponent("no-run", isDirectory: true).path
        XCTAssertThrowsError(try ReportGenerator.testReportHTML(runDir: missing)) { error in
            XCTAssertTrue(error is ReportGenerator.ReportError,
                          "missing run.json should surface a ReportError")
        }
    }

    // MARK: - Verify report

    func testVerifyReportContainsThumbnailMaxWidthAndEmbeddedImage() throws {
        // Build a verify dir with the four variant folders + one screenshot each.
        let verifyDir = tempDir.appendingPathComponent("verify", isDirectory: true)
        let variants = ["iphone-light", "iphone-dark", "ipad-light", "ipad-dark"]
        for variant in variants {
            let vdir = verifyDir.appendingPathComponent(variant, isDirectory: true)
            try FileManager.default.createDirectory(at: vdir, withIntermediateDirectories: true)
            try writePNG(to: vdir.appendingPathComponent("001_settings-screen.png"))
        }
        // Empty findings → status "All OK".
        try Data("[]".utf8).write(to: verifyDir.appendingPathComponent("findings.json"))

        let html = try ReportGenerator.verifyReportHTML(
            verifyDir: verifyDir.path,
            title: "Add Settings Toggle"
        )

        // Structural markers
        XCTAssertTrue(html.contains("<title>Verify: Add Settings Toggle</title>"),
                      "expected the title in the page title")
        XCTAssertTrue(html.contains("status-ok"), "empty findings.json should be All OK")
        XCTAssertTrue(html.contains("All OK"), "expected the All OK status label")
        XCTAssertTrue(html.contains("iPhone Light"), "expected the variant column headers")
        XCTAssertTrue(html.contains("settings screen"), "expected the derived check description")

        // The thumbnail max-width:220px sizing fix must be present.
        XCTAssertTrue(html.contains("max-width:220px"),
                      "verify report must keep the thumbnail max-width:220px sizing fix")

        // Base64 PNG embedding.
        XCTAssertTrue(html.contains("data:image/png;base64,"),
                      "expected variant screenshots to be embedded as Base64 data URIs")
    }

    func testVerifyReportFailSafeStatusWithoutFindings() throws {
        // No findings.json and no override → fail-safe "Issues Found".
        let verifyDir = tempDir.appendingPathComponent("verify-nofindings", isDirectory: true)
        let vdir = verifyDir.appendingPathComponent("iphone-light", isDirectory: true)
        try FileManager.default.createDirectory(at: vdir, withIntermediateDirectories: true)
        try writePNG(to: vdir.appendingPathComponent("001_home.png"))

        let html = try ReportGenerator.verifyReportHTML(verifyDir: verifyDir.path)
        XCTAssertTrue(html.contains("status-issue"), "missing findings.json must fail safe to Issues Found")
        XCTAssertTrue(html.contains("Issues Found"), "expected the Issues Found status label")
    }

    func testVerifyReportNonexistentDirThrows() {
        let missing = tempDir.appendingPathComponent("nope", isDirectory: true).path
        XCTAssertThrowsError(try ReportGenerator.verifyReportHTML(verifyDir: missing)) { error in
            XCTAssertTrue(error is ReportGenerator.ReportError,
                          "a missing verify dir should surface a ReportError")
        }
    }
}
