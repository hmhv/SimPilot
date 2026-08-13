// ReportGeneratorTests.swift
//
// Locks the report generation that moved INTO the sipi binary (STAGE REPORT):
// the test-run and verify HTML reports formerly produced by the loose
// interpreter scripts now come from SimCore.ReportGenerator. These build a small
// fixture run/verify directory on disk and assert the generated HTML carries the
// expected structural markers and Base64-embedded PNG.
//
// They also lock what makes the reports readable rather than merely present: a
// step card that names its action and how its verify checks landed, failing
// tests ahead of passing ones, light and dark side by side per device, an
// arrow-key-navigable lightbox group, a palette that follows the reader's colour
// scheme, and the ImageIO downscale that keeps a device-native capture from
// being embedded at full size.

import XCTest
import Foundation
import CoreGraphics
import ImageIO
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
        XCTAssertTrue(FileManager.default.fileExists(atPath: runDir.path + "/summary.json"),
                      "summary.json should be written beside report.html")
    }

    func testTestRunSummaryAndFailureHighlights() throws {
        let runDir = tempDir.appendingPathComponent("run-fail", isDirectory: true)
        let testDir = runDir.appendingPathComponent("login-flow", isDirectory: true)
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

        let run: [String: Any] = [
            "started": "2026-06-19T10:00:00+09:00",
            "finished": "2026-06-19T10:00:09+09:00",
            "device": "udid",
            "device-name": "iPhone 16",
            "device-runtime": "iOS 18.0",
            "tests": [["id": "login-flow", "passed": false, "duration": 9.0]],
            "summary": ["total": 1, "passed": 0, "failed": 1]
        ]
        try Data(JSONSerialization.data(withJSONObject: run))
            .write(to: runDir.appendingPathComponent("run.json"))

        let result: [String: Any] = [
            "id": "login-flow",
            "passed": false,
            "duration": 9.0,
            "steps": [[
                "passed": false,
                "action": "Tap Sign In",
                "duration": 2.0,
                "screenshot": "step-001.png",
                "failure-type": "verify",
                "attempted-methods": [["method": "tap-id", "value": "auth.sign-in"]],
                "verify": [["check": "Dashboard appears", "found": false]]
            ]]
        ]
        try Data(JSONSerialization.data(withJSONObject: result))
            .write(to: testDir.appendingPathComponent("result.json"))

        let summary = try ReportGenerator.testRunSummary(runDir: runDir.path)
        XCTAssertEqual(summary["status"] as? String, "fail")
        let failures = summary["top-failures"] as? [[String: Any]]
        XCTAssertEqual(failures?.first?["test"] as? String, "login-flow")
        XCTAssertEqual(failures?.first?["missing"] as? String, "Dashboard appears")
        XCTAssertEqual(failures?.first?["screenshot"] as? String, "login-flow/step-001.png")

        let html = try ReportGenerator.testReportHTML(runDir: runDir.path)
        XCTAssertTrue(html.contains("Failure Highlights"), "failed runs should render failure highlights before the table")
        XCTAssertTrue(html.contains("Dashboard appears"), "missing verify text should be shown in failure highlights")
    }

    func testTestReportMissingRunJSONThrows() {
        let missing = tempDir.appendingPathComponent("no-run", isDirectory: true).path
        XCTAssertThrowsError(try ReportGenerator.testReportHTML(runDir: missing)) { error in
            XCTAssertTrue(error is ReportGenerator.ReportError,
                          "missing run.json should surface a ReportError")
        }
    }

    // MARK: - Verify report

    func testVerifyReportPairsLightAndDarkPerDeviceRow() throws {
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
        XCTAssertTrue(html.contains("Findings"), "verify report should show findings above the screenshot grid")
        XCTAssertTrue(html.contains("No findings recorded."), "empty findings should be explicit in the report")
        XCTAssertTrue(html.contains("settings screen"), "expected the derived check description")

        // Appearance columns are grouped under their device, so light and dark
        // are adjacent and one check is one row.
        XCTAssertTrue(html.contains(">Light</th>"), "expected a Light column")
        XCTAssertTrue(html.contains(">Dark</th>"), "expected a Dark column")
        XCTAssertTrue(html.contains("colspan=\"2\" class=\"devstart\">iPhone</th>"),
                      "expected the device as a spanning header")
        XCTAssertTrue(html.contains("colspan=\"2\" class=\"devstart\">iPad</th>"),
                      "expected both devices on the same row")
        XCTAssertFalse(html.contains("<th>iPad Dark</th>"),
                       "the device should not be repeated per appearance column")
        XCTAssertEqual(html.components(separatedBy: "<tr data-lightbox-group>").count - 1, 1,
                       "one check is one row, so one lightbox group")

        // The thumbnail ceiling stays explicit, and matches the step cards in
        // the test report — a grid to scan, the lightbox to inspect.
        XCTAssertTrue(html.contains("max-width:200px"),
                      "verify thumbnails must keep an explicit max-width")

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
        XCTAssertTrue(html.contains("findings.json is missing"), "missing findings should be called out before screenshots")
    }

    func testVerifyReportRendersFindingsBeforeGrid() throws {
        let verifyDir = tempDir.appendingPathComponent("verify-findings", isDirectory: true)
        let vdir = verifyDir.appendingPathComponent("ipad-dark", isDirectory: true)
        try FileManager.default.createDirectory(at: vdir, withIntermediateDirectories: true)
        try writePNG(to: vdir.appendingPathComponent("001_settings-screen.png"))
        let findings: [[String: Any]] = [
            ["check": "settings-screen", "variant": "ipad-dark", "issue": "Toggle label is clipped"]
        ]
        try Data(JSONSerialization.data(withJSONObject: findings))
            .write(to: verifyDir.appendingPathComponent("findings.json"))

        let html = try ReportGenerator.verifyReportHTML(verifyDir: verifyDir.path)
        XCTAssertTrue(html.contains("Findings"), "findings section should be present")
        XCTAssertTrue(html.contains("Toggle label is clipped"), "finding issue text should be rendered")
        XCTAssertTrue(html.range(of: "Findings")!.lowerBound < html.range(of: "<table>")!.lowerBound,
                      "findings should appear before the screenshot grid")
    }

    func testVerifyReportNonexistentDirThrows() {
        let missing = tempDir.appendingPathComponent("nope", isDirectory: true).path
        XCTAssertThrowsError(try ReportGenerator.verifyReportHTML(verifyDir: missing)) { error in
            XCTAssertTrue(error is ReportGenerator.ReportError,
                          "a missing verify dir should surface a ReportError")
        }
    }

    // MARK: - Readability

    /// A step card used to say "Step 3 / 0.9s" while result.json already knew the
    /// action and how every verify check landed. Reading a run meant guessing
    /// what each screenshot was of.
    func testStepCardsNameTheirActionAndVerifyTally() throws {
        let runDir = tempDir.appendingPathComponent("run-actions", isDirectory: true)
        let testDir = runDir.appendingPathComponent("text-input", isDirectory: true)
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        try writeRunJSON(at: runDir, tests: [["id": "text-input", "passed": true, "duration": 2.0]],
                         summary: ["total": 1, "passed": 1, "failed": 0])
        try writePNG(to: testDir.appendingPathComponent("step-001.png"))
        try writePNG(to: testDir.appendingPathComponent("step-002.png"))
        let result: [String: Any] = [
            "id": "text-input", "passed": true, "duration": 2.0,
            "steps": [
                ["passed": true, "action": "tap id text-input.field", "screenshot": "step-001.png",
                 "duration": 0.5,
                 "verify": [["check": "contains: Network Probe", "found": true],
                            ["check": "contains: Text Input", "found": true]]],
                ["passed": true, "action": "type text", "screenshot": "step-002.png",
                 "duration": 1.5, "verify": []]
            ]
        ]
        try Data(JSONSerialization.data(withJSONObject: result))
            .write(to: testDir.appendingPathComponent("result.json"))

        let html = try ReportGenerator.testReportHTML(runDir: runDir.path)

        XCTAssertTrue(html.contains("tap id text-input.field"),
                      "the step card must name the action it captured")
        XCTAssertTrue(html.contains("type text"), "every step's action, not just the first")
        XCTAssertTrue(html.contains("✓2/2"),
                      "a step that asserted something should show how its checks landed")
        XCTAssertEqual(html.components(separatedBy: "class=\"tally").count - 1, 1,
                       "a step with no verify checks has no tally to show")
        XCTAssertTrue(html.contains("data-cap=\"text-input · step 1: tap id text-input.field\""),
                      "the lightbox caption should say which step and action is on screen")
    }

    /// The run table stays in run order — it is the index of the run — but the
    /// detail sections lead with what went wrong.
    func testFailingTestDetailsSortAheadOfPassingOnes() throws {
        let runDir = tempDir.appendingPathComponent("run-order", isDirectory: true)
        for tid in ["aa-pass", "zz-fail"] {
            let dir = runDir.appendingPathComponent(tid, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try writePNG(to: dir.appendingPathComponent("step-001.png"))
            let passed = tid == "aa-pass"
            let result: [String: Any] = [
                "id": tid, "passed": passed, "duration": 1.0,
                "steps": [["passed": passed, "action": "tap Go", "screenshot": "step-001.png",
                           "duration": 1.0, "failure-type": passed ? "" : "verify-failed"]]
            ]
            try Data(JSONSerialization.data(withJSONObject: result))
                .write(to: dir.appendingPathComponent("result.json"))
        }
        try writeRunJSON(at: runDir,
                         tests: [["id": "aa-pass", "passed": true, "duration": 1.0],
                                 ["id": "zz-fail", "passed": false, "duration": 1.0]],
                         summary: ["total": 2, "passed": 1, "failed": 1])

        let html = try ReportGenerator.testReportHTML(runDir: runDir.path)

        let failDetail = html.range(of: "id=\"test-zz-fail\"")
        let passDetail = html.range(of: "id=\"test-aa-pass\"")
        XCTAssertNotNil(failDetail, "expected an anchored detail section per test")
        XCTAssertNotNil(passDetail)
        XCTAssertTrue(failDetail!.lowerBound < passDetail!.lowerBound,
                      "the failing test's detail must come first")

        let passLink = html.range(of: "href=\"#test-aa-pass\"")
        let failLink = html.range(of: "href=\"#test-zz-fail\"")
        XCTAssertNotNil(passLink, "the table should link into the detail sections")
        XCTAssertTrue(passLink!.lowerBound < failLink!.lowerBound,
                      "the table itself stays in run order")
    }

    /// Both reports are read next to the screenshots they embed, including dark
    /// ones, so the page follows the reader's colour scheme.
    func testBothReportsFollowTheReadersColorScheme() throws {
        let runDir = tempDir.appendingPathComponent("run-dark", isDirectory: true)
        try FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true)
        try writeRunJSON(at: runDir, tests: [], summary: ["total": 0, "passed": 0, "failed": 0])
        let testHTML = try ReportGenerator.testReportHTML(runDir: runDir.path)

        let verifyDir = tempDir.appendingPathComponent("verify-dark", isDirectory: true)
        let vdir = verifyDir.appendingPathComponent("iphone-dark", isDirectory: true)
        try FileManager.default.createDirectory(at: vdir, withIntermediateDirectories: true)
        try writePNG(to: vdir.appendingPathComponent("001_home.png"))
        let verifyHTML = try ReportGenerator.verifyReportHTML(verifyDir: verifyDir.path)

        for (name, html) in [("test run", testHTML), ("verify", verifyHTML)] {
            XCTAssertTrue(html.contains("background:var(--bg)"),
                          "\(name) report should paint from tokens, not hardcoded light colours")

            // All three reader states: no choice made, chose dark, chose light.
            XCTAssertTrue(html.contains("@media (prefers-color-scheme:dark){:root:not([data-theme=\"light\"])"),
                          "\(name) report should follow the system until the reader chooses")
            XCTAssertTrue(html.contains(":root[data-theme=\"dark\"]"),
                          "\(name) report should honour an explicit dark choice over the system")

            // The toggle, and the boot script that applies a remembered choice
            // before the body paints.
            XCTAssertTrue(html.contains("id=\"theme-toggle\"") && html.contains("toggleTheme()"),
                          "\(name) report should carry a colour-scheme toggle")
            XCTAssertTrue(html.contains("localStorage.getItem('sipi-report-theme')"),
                          "\(name) report should restore the remembered choice")
            let bootScript = try XCTUnwrap(html.range(of: "sipi-report-theme"))
            let bodyStart = try XCTUnwrap(html.range(of: "<body>"))
            XCTAssertTrue(bootScript.lowerBound < bodyStart.lowerBound,
                          "\(name) report must apply the theme before the body paints")
        }
    }

    /// The lightbox walks whatever set the reader was already comparing: a
    /// test's step strip, or one row of the verify grid.
    func testLightboxGroupsAreArrowNavigable() throws {
        let verifyDir = tempDir.appendingPathComponent("verify-nav", isDirectory: true)
        for variant in ["iphone-light", "iphone-dark"] {
            let vdir = verifyDir.appendingPathComponent(variant, isDirectory: true)
            try FileManager.default.createDirectory(at: vdir, withIntermediateDirectories: true)
            try writePNG(to: vdir.appendingPathComponent("001_home.png"))
        }
        let html = try ReportGenerator.verifyReportHTML(verifyDir: verifyDir.path)

        XCTAssertTrue(html.contains("data-lightbox-group"),
                      "a comparable set must be marked as one lightbox group")
        XCTAssertTrue(html.contains("moveLightbox"), "expected arrow-key navigation")
        XCTAssertTrue(html.contains("ArrowRight") && html.contains("ArrowLeft"),
                      "both arrow keys should be bound")
        XCTAssertTrue(html.contains("data-cap=\"home · iPhone Light\""),
                      "each image should caption itself for the lightbox")
    }

    // MARK: - Screenshot downscale

    func testOversizedCaptureIsDownscaledBeforeEmbedding() throws {
        let big = try noisyPNGData(width: 400, height: 400)
        let shrunk = ReportGenerator.downscaledPNG(big, maxPixel: 100)
        let unwrapped = try XCTUnwrap(shrunk, "an oversized capture should be re-encoded smaller")
        XCTAssertLessThan(unwrapped.count, big.count,
                          "the re-encode is only worth embedding if it is smaller")

        let source = try XCTUnwrap(CGImageSourceCreateWithData(unwrapped as CFData, nil))
        let props = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let width = try XCTUnwrap(props[kCGImagePropertyPixelWidth] as? Int)
        let height = try XCTUnwrap(props[kCGImagePropertyPixelHeight] as? Int)
        XCTAssertLessThanOrEqual(max(width, height), 100, "long side must respect the ceiling")
    }

    func testCaptureWithinTheCeilingIsEmbeddedUnchanged() throws {
        let small = try noisyPNGData(width: 80, height: 80)
        XCTAssertNil(ReportGenerator.downscaledPNG(small, maxPixel: 100),
                     "an image already within the ceiling should be embedded as-is")
        XCTAssertNil(ReportGenerator.downscaledPNG(Data("not a png".utf8), maxPixel: 100),
                     "unreadable bytes should fall back to embedding the original")
    }

    func testThumbnailCeilingCoversTheGridAtRetinaDensity() {
        XCTAssertEqual(ReportGenerator.thumbnailMaxPixel, 600,
                       "600px covers a 200px thumbnail at Retina density with room to spare")
    }

    // MARK: - Fixtures

    private func writeRunJSON(at runDir: URL, tests: [[String: Any]],
                              summary: [String: Any]) throws {
        try FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true)
        let run: [String: Any] = [
            "started": "2026-06-19T10:00:00+09:00",
            "device": "udid",
            "device-name": "iPhone 16",
            "device-runtime": "iOS 18.0",
            "suite": "Fixture Suite",
            "commit": "abc1234",
            "tests": tests,
            "summary": summary
        ]
        try Data(JSONSerialization.data(withJSONObject: run))
            .write(to: runDir.appendingPathComponent("run.json"))
    }

    /// A deterministic noisy PNG. Noise matters: a flat colour compresses to
    /// almost nothing, and then a downscale cannot come out smaller.
    private func noisyPNGData(width: Int, height: Int) throws -> Data {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        for y in 0..<height {
            for x in 0..<width {
                let i = y * bytesPerRow + x * 4
                pixels[i] = UInt8((x * 7 + y * 13) % 256)
                pixels[i + 1] = UInt8((x * 31 + y * 17) % 256)
                pixels[i + 2] = UInt8((x ^ y) % 256)
                pixels[i + 3] = 255
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        let image = try XCTUnwrap(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let out = NSMutableData()
        let dest = try XCTUnwrap(
            CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest), "failed to encode the fixture PNG")
        return out as Data
    }
}
