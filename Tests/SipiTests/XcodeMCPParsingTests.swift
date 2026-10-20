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

    // MARK: - JSON listing (Xcode 27 RC)

    private let json = """
    {
      "openWorkspaces" : [],
      "permission" : {
        "enabled" : true,
        "permittedAgents" : [
          {
            "id" : "C5A3BBB5-2C74-49BB-B735-FF89B0FB64FB",
            "trust" : {
              "unsigned" : {
                "expiration" : 810774804.045319,
                "path" : "/Users/u/.local/bin/sipi",
                "sha256" : "1f09d3fce3aea0d8503b47f8f240493a66201862e6936a714b116616e3faa024"
              }
            }
          }
        ],
        "permittedFolders" : [
          { "expiration" : 810774804.06071, "id" : "57BAA576-...", "subtreeRoot" : "/Users/u/projects" }
        ],
        "unsafeAlwaysAllowAllAgents" : false
      },
      "running" : true
    }
    """

    func testTheJSONListingCarriesPathAndDigest() {
        let parsed = XcodeMCP.grants(fromJSON: json)
        XCTAssertEqual(parsed?.enabled, true)
        XCTAssertEqual(parsed?.grants.agents, [
            .init(id: "C5A3BBB5-2C74-49BB-B735-FF89B0FB64FB",
                  path: "/Users/u/.local/bin/sipi",
                  sha256: "1f09d3fce3aea0d8503b47f8f240493a66201862e6936a714b116616e3faa024"),
        ])
        XCTAssertEqual(parsed?.grants.unsafeAllowAll, false)
    }

    func testAMatchingDigestIsACertainGrantEvenFromAnotherPath() {
        // The digest identifies the file; the path Xcode recorded may be a
        // different spelling of it (or the binary may have been copied).
        let grants = XcodeMCP.grants(fromJSON: json)!.grants
        XCTAssertEqual(
            grants.match(executable: "/somewhere/else/sipi",
                         sha256: "1F09D3FCE3AEA0D8503B47F8F240493A66201862E6936A714B116616E3FAA024"),
            .digest
        )
    }

    func testAMatchingPathWithADifferentDigestIsAStaleGrant() {
        // Same path, different build: Xcode refuses the new binary, and with
        // digests on both sides sipi can say so outright.
        let grants = XcodeMCP.grants(fromJSON: json)!.grants
        XCTAssertEqual(grants.match(executable: "/Users/u/.local/bin/sipi", sha256: "abcd"), .stale)
        XCTAssertEqual(grants.match(executable: "/usr/local/bin/sipi", sha256: "abcd"), .none)
    }

    func testAPathMatchWithoutADigestToCheckStaysALikelyGrant() {
        // A caller that could not hash itself cannot tell a stale grant from a
        // live one, and neither can a record that carries no digest.
        XCTAssertEqual(
            XcodeMCP.grants(fromJSON: json)!.grants.match(executable: "/Users/u/.local/bin/sipi", sha256: nil),
            .path
        )
        let undigested = XcodeMCP.Grants(agents: [.init(id: "1", path: "/Users/u/.local/bin/sipi", sha256: nil)])
        XCTAssertEqual(undigested.match(executable: "/Users/u/.local/bin/sipi", sha256: "abcd"), .path)
    }

    func testTheTextListingKeepsTheIdAndTheDigestPrefix() {
        let agents = XcodeMCP.grants(fromText: listing).agents
        XCTAssertEqual(agents.count, 2)
        XCTAssertEqual(agents[1].id, "C2D5E452-...")
        XCTAssertEqual(agents[1].path, "/Users/u/.local/bin/sipi")
        XCTAssertEqual(agents[1].sha256, "fe5ec1bbc28d")
    }

    func testATruncatedDigestStillTellsBuildsApart() {
        let grants = XcodeMCP.grants(fromText: listing)
        XCTAssertEqual(
            grants.match(executable: "/Users/u/.local/bin/sipi",
                         sha256: "fe5ec1bbc28d0000000000000000000000000000000000000000000000000000"),
            .digest
        )
        XCTAssertEqual(grants.match(executable: "/Users/u/.local/bin/sipi", sha256: "abcd" + String(repeating: "0", count: 60)), .stale)
    }

    func testJSONIsFoundInsideAWarningLine() {
        // `capture` merges stderr into the text, and `status` puts warnings there.
        XCTAssertEqual(XcodeMCP.grants(fromJSON: "warning: something\n" + json + "\n")?.grants.agents.count, 1)
    }

    func testAnApprovalIsCreditedOnlyToANewOrDigestMatchedGrant() {
        let stale = XcodeMCP.Grants(agents: [.init(id: "old", path: "/Users/u/.local/bin/sipi", sha256: nil)])
        // The same listing again: nothing new, not credited.
        XCTAssertFalse(XcodeMCP.isNewlyApproved(stale, since: stale, executable: "/Users/u/.local/bin/sipi", sha256: "abcd"))
        // A second record at the path with a new id: credited.
        var grown = stale
        grown.agents.append(.init(id: "new", path: "/Users/u/.local/bin/sipi", sha256: nil))
        XCTAssertTrue(XcodeMCP.isNewlyApproved(grown, since: stale, executable: "/Users/u/.local/bin/sipi", sha256: "abcd"))
        // A digest match is credited even when it was already listed.
        let mine = XcodeMCP.Grants(agents: [.init(id: "old", path: "/elsewhere/sipi", sha256: "abcd1234ef")])
        XCTAssertTrue(XcodeMCP.isNewlyApproved(mine, since: mine, executable: "/Users/u/.local/bin/sipi", sha256: "abcd1234ef00"))
        // A record with no id cannot be told from a pre-existing one: not credited.
        let anonymous = XcodeMCP.Grants(agents: [.init(id: nil, path: "/Users/u/.local/bin/sipi", sha256: nil)])
        XCTAssertFalse(XcodeMCP.isNewlyApproved(anonymous, since: anonymous, executable: "/Users/u/.local/bin/sipi", sha256: "abcd"))
        XCTAssertFalse(XcodeMCP.isNewlyApproved(anonymous, since: XcodeMCP.Grants(), executable: "/Users/u/.local/bin/sipi", sha256: "abcd"))
        // A stale digest at the path is never credited.
        let other = XcodeMCP.Grants(agents: [.init(id: "old", path: "/Users/u/.local/bin/sipi", sha256: "ffffffffffff")])
        XCTAssertFalse(XcodeMCP.isNewlyApproved(other, since: XcodeMCP.Grants(), executable: "/Users/u/.local/bin/sipi", sha256: "abcd1234ef00"))
    }

    func testTheTextListingIsNotMistakenForJSON() {
        XCTAssertNil(XcodeMCP.grants(fromJSON: listing))
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
