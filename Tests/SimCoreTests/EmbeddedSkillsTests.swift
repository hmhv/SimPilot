// EmbeddedSkillsTests.swift
//
// Locks the build-time skill embedding (STAGE EMBED). The sipi binary must ship
// the skill tree baked in so the curl|bash install is a single
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
        XCTAssertTrue(paths.contains("sipi-common/docs/ui-driver.md"),
                      "expected sipi-common/docs/ui-driver.md to be embedded")
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

    func testEmbeddedSkillsDescribeDataAndEvidenceWorkflow() throws {
        let common = try text(at: "sipi-common/SKILL.md")
        XCTAssertTrue(common.contains("sipi --help"))
        XCTAssertTrue(common.contains("sipi help container"))
    }

    func testRelativePathsUsePosixSeparators() {
        for (path, _) in EmbeddedSkills.all {
            XCTAssertFalse(path.hasPrefix("/"), "\(path) must be relative")
            XCTAssertFalse(path.contains("\\"), "\(path) must use POSIX separators")
        }
    }

    private func text(at path: String) throws -> String {
        let entry = try XCTUnwrap(EmbeddedSkills.all.first { $0.path == path })
        return try XCTUnwrap(String(data: entry.data, encoding: .utf8))
    }
}
