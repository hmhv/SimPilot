// XcodeMCPCommand.swift
//
// `sipi xcode-mcp` — check, and obtain, access to Xcode's own device-interaction
// service. sipi uses that service for exactly one thing: typing into a simulator
// whose keyboard HID has stopped accepting input, and typing text the guest's
// keyboard layout would otherwise mangle. See XcodeMCP.swift.

import ArgumentParser
import Foundation
import SimBridge

extension Sipi {
    struct XcodeMCPCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "xcode-mcp",
            abstract: "Check or obtain access to Xcode's device-interaction service (used as a keyboard fallback).",
            discussion: """
            sipi drives simulators on its own. This service covers the one case it
            cannot: a simulator that has stopped accepting keyboard HID, where
            paste, per-key typing and select-all all leave the field untouched
            while this service still types into it. It also ignores the guest
            keyboard layout, which per-key HID does not.

            Three things must be true before sipi can use it:

              1. Xcode 27 or later is selected (`xcode-select -p`).
              2. Headless mode is on:  sudo xcrun mcp-server enable
              3. THIS binary is approved. Run `sipi xcode-mcp --approve <path to
                 an .xcodeproj or .xcworkspace>` and accept the prompt. The
                 project is opened only to raise that prompt and is closed again
                 straight away.

            Approval is tied to the exact binary, so `sipi update` or a rebuild
            means approving once more. Everything sipi does apart from this
            keyboard fallback works without any of it.
            """
        )

        @Option(
            name: .customLong("approve"),
            help: "Path to an .xcodeproj or .xcworkspace, opened only to raise the approval prompt."
        )
        var approveWith: String?

        func run() throws {
            let developerDir = SPSimBridge.defaultDeveloperDir()

            guard let approveWith else {
                switch XcodeMCP.readiness(developerDir: developerDir) {
                case .ready:
                    print("Xcode MCP service: ready.")
                    print("  This binary is approved; `sipi type --xcode-mcp` and the automatic fallback are available.")
                case .notApprovedYet:
                    print("Xcode MCP service: enabled, this binary not approved.")
                    print("  Run `sipi xcode-mcp --approve <path to an .xcodeproj or .xcworkspace>` once.")
                    print("  The grant is tied to this exact binary, so an update or rebuild needs it again.")
                case .unavailable(let reason):
                    print("Xcode MCP service: unavailable.")
                    print("  \(reason.description)")
                }
                return
            }

            // Xcode's service takes an absolute path, so a relative one that
            // exists here would still be rejected there.
            let path = URL(
                fileURLWithPath: (approveWith as NSString).expandingTildeInPath
            ).standardizedFileURL.path
            guard FileManager.default.fileExists(atPath: path) else {
                throw ValidationError("No project at '\(path)'. Pass an .xcodeproj or .xcworkspace.")
            }

            do {
                let workspace = try XcodeMCP.requestApproval(projectPath: path, developerDir: developerDir)
                print("Approved. Xcode opened '\(workspace)' to ask, and it has been closed again.")
                print("`sipi type --xcode-mcp` is now available for this binary.")
            } catch let reason as XcodeMCP.Unavailable {
                throw ValidationError(reason.description)
            }
        }
    }
}
