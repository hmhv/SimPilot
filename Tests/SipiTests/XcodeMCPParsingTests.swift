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
