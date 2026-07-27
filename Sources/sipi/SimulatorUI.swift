// SimulatorUI.swift
//
// `sipi open-ui` — open the Xcode app that shows a simulator's screen.
//
// sipi drives simulators headlessly: it boots and talks to devices through
// CoreSimulator, so no window is ever required. When a human does want to look
// at the device, the app to open depends on the Xcode generation:
//
//   Xcode 27+   Device Hub (`<Xcode>.app/Contents/Applications/DeviceHub.app`)
//               replaced Simulator.app and manages devices + simulators together.
//   Xcode <=26  Simulator.app (`<Xcode>.app/Contents/Developer/Applications/`).
//
// `open -a Simulator` — still the reflex, and still in older docs — simply fails
// on Xcode 27 ("Unable to find application named 'Simulator'"), which reads as
// "the simulator is gone" when it is booted and driveable the whole time. This
// command resolves whichever app the active Xcode actually ships.

import ArgumentParser
import Foundation
import SimBridge

/// The GUI app that can display a simulator screen for the active Xcode.
struct SimulatorUIApp {
    /// Display name (`Device Hub` / `Simulator`).
    var name: String
    /// Absolute path to the `.app` bundle.
    var path: String

    /// Resolve the app shipped by `developerDir`'s Xcode, newest layout first.
    /// Returns nil when neither app is present (a Command Line Tools-only
    /// install, for example) — headless driving still works, so callers treat
    /// this as informational.
    static func resolve(developerDir: String = SPSimBridge.defaultDeveloperDir()) -> SimulatorUIApp? {
        for candidate in candidates(developerDir: developerDir) {
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    /// Every location checked, in priority order. Exposed so a failure can say
    /// where it looked.
    static func candidates(developerDir: String) -> [SimulatorUIApp] {
        let developer = URL(fileURLWithPath: developerDir).standardizedFileURL
        // <Xcode>.app/Contents/Applications/DeviceHub.app — sibling of Developer/.
        let contents = developer.deletingLastPathComponent()
        return [
            SimulatorUIApp(
                name: "Device Hub",
                path: contents.appendingPathComponent("Applications/DeviceHub.app").path
            ),
            SimulatorUIApp(
                name: "Simulator",
                path: developer.appendingPathComponent("Applications/Simulator.app").path
            )
        ]
    }
}

extension Sipi {
    struct OpenUI: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "open-ui",
            abstract: "Open the Xcode app that shows simulator screens (Device Hub on Xcode 27+, Simulator.app before).",
            discussion: """
            sipi drives simulators headlessly — booting, tapping, and screenshots all
            work with no window open. Use this only to eyeball a device yourself.

            Xcode 27 removed Simulator.app in favor of Device Hub, so `open -a Simulator`
            fails there even though the simulator is booted and driveable. This command
            opens whichever app the active Xcode ships.

            Selecting a specific device inside the window is a manual step: neither app
            has a documented way to be pointed at a UDID from the command line.
            """
        )

        @Flag(name: .long, help: "Emit the resolved app as JSON ({ name, path, opened }).")
        var json = false

        @Flag(name: .long, help: "Only resolve and report the app; do not open it.")
        var printOnly = false

        func run() throws {
            let developerDir = SPSimBridge.defaultDeveloperDir()
            guard let app = SimulatorUIApp.resolve(developerDir: developerDir) else {
                let looked = SimulatorUIApp.candidates(developerDir: developerDir)
                    .map { $0.path }
                    .joined(separator: ", ")
                throw ValidationError(
                    "No simulator UI app found for the active Xcode (\(developerDir)). "
                    + "Looked for: \(looked). Headless driving is unaffected."
                )
            }

            var opened = false
            if !printOnly {
                try open(app)
                opened = true
            }

            if json {
                let data = try JSONSerialization.data(
                    withJSONObject: ["name": app.name, "path": app.path, "opened": opened],
                    options: [.prettyPrinted, .sortedKeys]
                )
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            } else if opened {
                print("opened \(app.name) (\(app.path))")
            } else {
                print("\(app.name) (\(app.path))")
            }
        }

        /// Launch the resolved bundle with `/usr/bin/open -a <path>`. Uses the path
        /// rather than the name because the name is exactly what fails on Xcode 27.
        private func open(_ app: SimulatorUIApp) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", app.path]
            let errorPipe = Pipe()
            process.standardError = errorPipe
            do {
                try process.run()
            } catch {
                throw ValidationError("Failed to launch /usr/bin/open: \(error.localizedDescription)")
            }
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let stderr = String(decoding: errorData, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw ValidationError(
                    "`open -a \(app.path)` exited \(process.terminationStatus)"
                    + (stderr.isEmpty ? "" : ": \(stderr)")
                )
            }
        }
    }
}
