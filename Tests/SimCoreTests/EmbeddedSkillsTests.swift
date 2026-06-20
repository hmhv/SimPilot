// EmbeddedSkillsTests.swift
//
// Locks the build-time skill embedding (STAGE EMBED). The sipi binary must ship
// the three skill trees baked in so the curl|bash install is a single
// self-contained download. These assertions fail if the EmbedSkillsPlugin /
// simskillsgen generation stops producing the current skill files — e.g. a
// broken symlink, an empty tree, or a lost relative-path / executable bit.

import XCTest
import Foundation
@testable import SimSkills

final class EmbeddedSkillsTests: XCTestCase {

    func testAllIsNonEmpty() {
        XCTAssertFalse(EmbeddedSkills.all.isEmpty,
                       "EmbeddedSkills.all must contain the embedded skill files")
    }

    func testContainsKnownEntries() {
        let paths = Set(EmbeddedSkills.all.map { $0.path })
        XCTAssertTrue(paths.contains("sipi-common/SKILL.md"),
                      "expected sipi-common/SKILL.md to be embedded")
        XCTAssertTrue(paths.contains("sipi-test/docs/run.md"),
                      "expected sipi-test/docs/run.md to be embedded")
        XCTAssertTrue(paths.contains("sipi-verify/SKILL.md"),
                      "expected sipi-verify/SKILL.md to be embedded")
    }

    func testAllThreeSkillTreesArePresent() {
        let paths = EmbeddedSkills.all.map { $0.path }
        for skill in ["sipi-common", "sipi-test", "sipi-verify"] {
            XCTAssertTrue(paths.contains { $0.hasPrefix("\(skill)/") },
                          "expected at least one file under \(skill)/")
        }
    }

    func testEntriesCarryNonEmptyData() {
        for (path, data) in EmbeddedSkills.all {
            XCTAssertFalse(data.isEmpty, "embedded file \(path) must not be empty")
        }
    }

    func testKnownMarkdownEntryDecodesToText() {
        guard let entry = EmbeddedSkills.all.first(where: { $0.path == "sipi-common/SKILL.md" }) else {
            return XCTFail("sipi-common/SKILL.md not embedded")
        }
        let text = String(data: entry.data, encoding: .utf8)
        XCTAssertNotNil(text, "sipi-common/SKILL.md must decode as UTF-8 text")
    }

    func testRelativePathsUsePosixSeparators() {
        for (path, _) in EmbeddedSkills.all {
            XCTAssertFalse(path.hasPrefix("/"), "\(path) must be relative")
            XCTAssertFalse(path.contains("\\"), "\(path) must use POSIX separators")
        }
    }

    func testReportScriptsNoLongerEmbedded() {
        // Report/validate generation moved INTO the sipi binary as the
        // `report` / `verify-report` / `validate` subcommands (SimCore
        // ReportGenerator / ResultValidator). The loose interpreter scripts were
        // deleted from the skill trees, so they must no longer be embedded.
        let paths = Set(EmbeddedSkills.all.map { $0.path })
        XCTAssertFalse(paths.contains("sipi-test/scripts/generate_test_report.swift"),
                       "generate_test_report.swift must no longer be embedded (folded into `sipi report`)")
        XCTAssertFalse(paths.contains("sipi-verify/scripts/generate_verify_report.swift"),
                       "generate_verify_report.swift must no longer be embedded (folded into `sipi verify-report`)")
        XCTAssertFalse(paths.contains("sipi-test/scripts/validate_simpilot_results.swift"),
                       "validate_simpilot_results.swift must no longer be embedded (folded into `sipi validate`)")
    }
}
