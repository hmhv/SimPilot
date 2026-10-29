// XcodeMCPParsingTests.swift
//
// Xcode's MCP service answers some calls with JSON and others with plain text,
// and the two are easy to confuse — the first attempt at this parsed the
// workspace listing as JSON, which silently never matched, so the workspace
// `sipi xcode-mcp --approve` opens stayed open in Xcode. These lock the shapes
// that were actually measured: the text listing against Xcode 27.0 beta 6, the
// JSON listing against Xcode 27.0 RC (27A266a).

import XCTest
@testable import sipi

final class XcodeMCPParsingTests: XCTestCase {

    func testWorkspaceIdentifierIsReadFromThePlainTextListing() {
        let reply = "* workspaceIdentifier: workspace-18VxbuBVv2, workspacePath: /tmp/probe/App.xcodeproj"
        XCTAssertEqual(
            XcodeMCP.workspaceIdentifier(matching: "/tmp/probe/App.xcodeproj", in: reply),
            "workspace-18VxbuBVv2"
        )
    }

    func testAPathThatIsNotListedHasNoIdentifier() {
        let reply = "* workspaceIdentifier: workspace-1, workspacePath: /tmp/probe/Other.xcodeproj"
        XCTAssertNil(XcodeMCP.workspaceIdentifier(matching: "/tmp/probe/App.xcodeproj", in: reply))
    }

    func testTheEmptyListingIsNotMistakenForAMatch() {
        XCTAssertNil(
            XcodeMCP.workspaceIdentifier(
                matching: "/tmp/probe/App.xcodeproj",
                in: "No workspaces are currently open."
            )
        )
    }

    func testTheRightWorkspaceIsPickedOutOfSeveral() {
        let reply = """
        * workspaceIdentifier: workspace-1, workspacePath: /tmp/probe/One.xcodeproj
        * workspaceIdentifier: workspace-2, workspacePath: /tmp/probe/Two.xcodeproj
        """
        XCTAssertEqual(
            XcodeMCP.workspaceIdentifier(matching: "/tmp/probe/Two.xcodeproj", in: reply),
            "workspace-2"
        )
    }

    // MARK: - approval listing

    func testUnsafeModeApprovesEveryAgent() {
        let unsafe = """
        Permission: enabled (unsafe: always allow all agents)
        mcp-server: running
        """
        XCTAssertNotEqual(XcodeMCP.grants(fromText: unsafe).match(executable: "/anything", sha256: nil), .none)
    }

    func testADisabledServiceIsReportedFromJSON() {
        let disabled = #"{"permission":{"enabled":false,"permittedAgents":[],"unsafeAlwaysAllowAllAgents":false},"running":false}"#
        XCTAssertEqual(XcodeMCP.grants(fromJSON: disabled)?.enabled, false)
    }

    func testUnsafeModeInJSONApprovesEveryAgent() {
        let unsafe = #"{"permission":{"enabled":true,"permittedAgents":[],"unsafeAlwaysAllowAllAgents":true},"running":true}"#
        XCTAssertEqual(XcodeMCP.grants(fromJSON: unsafe)?.grants.match(executable: "/anything", sha256: nil), .digest)
    }

    func testAGrantRecordedUnderTheResolvedPathMatchesTheSymlink() throws {
        // Xcode records the resolved path. SwiftPM's `.build/release/sipi` is a
        // symlink into `.build/out/Products/Release/`, so a straight string
        // comparison reported an approved build as not approved.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sipi-xcode-mcp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("real"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let real = dir.appendingPathComponent("real/sipi")
        try Data("x".utf8).write(to: real)
        let link = dir.appendingPathComponent("sipi")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let grants = XcodeMCP.Grants(agents: [.init(id: "1", path: real.resolvingSymlinksInPath().path, sha256: nil)])
        XCTAssertEqual(grants.match(executable: link.path, sha256: nil), .path)
    }
}
