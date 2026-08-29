// XcodeMCPParsingTests.swift
//
// Xcode's MCP service answers some calls with JSON and others with plain text,
// and the two are easy to confuse — the first attempt at this parsed the
// workspace listing as JSON, which silently never matched, so the workspace
// `sipi xcode-mcp --approve` opens stayed open in Xcode. These lock the shape
// that was actually measured against Xcode 27.0 beta 6.

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

    private let listing = """
    Permission: enabled
    Permitted agents:
      95A5E505-...: unsigned /opt/homebrew/bin/python3 39d850585e74…
      C2D5E452-...: unsigned /Users/u/.local/bin/sipi fe5ec1bbc28d… (expires 2026-08-30 03:38:17 +0000)
    Permitted folders:
      BC75CE42-...: /Users/u/projects
    mcp-server: running
    """

    func testAPermittedAgentIsRecognised() {
        XCTAssertTrue(XcodeMCP.hasGrant(in: listing, executable: "/Users/u/.local/bin/sipi"))
    }

    func testAnAgentThatIsNotListedIsNotApproved() {
        XCTAssertFalse(XcodeMCP.hasGrant(in: listing, executable: "/usr/local/bin/sipi"))
    }

    func testAPathThatMerelyContainsOursIsNotOurs() {
        // `/usr/local/bin/sipi` must not be satisfied by a grant for
        // `/usr/local/bin/sipi-debug`, which contains it as a substring.
        let neighbour = """
        Permission: enabled
        Permitted agents:
          C2D5E452-...: unsigned /Users/u/.local/bin/sipi-debug fe5ec1bbc28d… (expires 2026-08-30 03:38:17 +0000)
        mcp-server: running
        """
        XCTAssertFalse(XcodeMCP.hasGrant(in: neighbour, executable: "/Users/u/.local/bin/sipi"))
    }

    func testAPathWithSpacesIsReadWhole() {
        let spaced = """
        Permission: enabled
        Permitted agents:
          C2D5E452-...: unsigned /Users/u/My Tools/sipi fe5ec1bbc28d… (expires 2026-08-30 03:38:17 +0000)
        mcp-server: running
        """
        XCTAssertTrue(XcodeMCP.hasGrant(in: spaced, executable: "/Users/u/My Tools/sipi"))
    }

    func testAPathOutsideThePermittedAgentsSectionDoesNotCount() {
        // A pending request names the same executable. Matching anywhere in the
        // blob would report a request that is still waiting as a granted one.
        let pending = """
        Permission: enabled
        Pending approvals:
          11111111-...: unsigned /Users/u/.local/bin/sipi aaaaaaaaaaaa…
        Permitted folders:
          BC75CE42-...: /Users/u/projects
        mcp-server: running
        """
        XCTAssertFalse(XcodeMCP.hasGrant(in: pending, executable: "/Users/u/.local/bin/sipi"))
    }

    func testUnsafeModeApprovesEveryAgent() {
        let unsafe = """
        Permission: enabled (unsafe: always allow all agents)
        mcp-server: running
        """
        XCTAssertTrue(XcodeMCP.hasGrant(in: unsafe, executable: "/anything"))
    }

    func testUnsafeIsReadFromThePermissionLineOnly() {
        // A permitted folder whose path contains the words must not turn every
        // unapproved binary into an approved one.
        let misleading = """
        Permission: enabled
        Permitted folders:
          BC75CE42-...: /Users/u/projects/unsafe-allow-list
        mcp-server: running
        """
        XCTAssertFalse(XcodeMCP.hasGrant(in: misleading, executable: "/Users/u/.local/bin/sipi"))
    }

    func testOnlyAFailureOfTheTypingCallBlocksARetry() {
        // Everything before the text is sent is safe to retry; once the typing
        // command has been issued the text may already be in the field.
        XCTAssertTrue(XcodeMCP.isBeforeTyping(.notEnabled))
        XCTAssertTrue(XcodeMCP.isBeforeTyping(.notApproved("x")))
        XCTAssertTrue(XcodeMCP.isBeforeTyping(.approvalPending))
        XCTAssertTrue(XcodeMCP.isBeforeTyping(.failed("DeviceInteractionStartSession: busy")))
        XCTAssertFalse(XcodeMCP.isBeforeTyping(.failed("DeviceInteractionSynthesize: timed out")))
    }
}
