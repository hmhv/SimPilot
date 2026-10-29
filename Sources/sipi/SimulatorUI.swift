// SimulatorUI.swift
//
// `sipi open-ui` — open the Xcode app that shows a simulator's screen.
//
// sipi drives simulators headlessly: it boots and talks to devices through
// CoreSimulator, so no window is ever required. When a human does want to look
// at the device, Device Hub (`<Xcode>.app/Contents/Applications/DeviceHub.app`)
// shows it. `open -a Simulator` — still the reflex — fails ("Unable to find
// application named 'Simulator'"), which reads as "the simulator is gone" when
// it is booted and driveable the whole time.

import ArgumentParser
import Foundation
import SimBridge

/// The GUI app that can display a simulator screen for the active Xcode.
struct SimulatorUIApp {
    /// Display name.
    var name: String
    /// Absolute path to the `.app` bundle.
    var path: String

    /// Device Hub in `developerDir`'s Xcode, or nil when it is absent (a Command
    /// Line Tools-only install, for example) — headless driving still works, so
    /// callers treat this as informational.
    static func resolve(developerDir: String = SPSimBridge.defaultDeveloperDir()) -> SimulatorUIApp? {
        let app = deviceHub(developerDir: developerDir)
        return FileManager.default.fileExists(atPath: app.path) ? app : nil
    }

    static func deviceHub(developerDir: String) -> SimulatorUIApp {
        // <Xcode>.app/Contents/Applications/DeviceHub.app — sibling of Developer/.
        let contents = URL(fileURLWithPath: developerDir).standardizedFileURL.deletingLastPathComponent()
        return SimulatorUIApp(name: "Device Hub", path: contents.appendingPathComponent("Applications/DeviceHub.app").path)
    }
}

extension Sipi {
    struct OpenUI: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "open-ui",
            abstract: "Open Device Hub, the Xcode window that shows simulator screens.",
            discussion: """
            sipi drives simulators headlessly — booting, tapping, and screenshots all
            work with no window open. Use this only to eyeball a device yourself.

            Xcode 27 removed Simulator.app in favor of Device Hub, so `open -a Simulator`
            fails even though the simulator is booted and driveable.

            Selecting a specific device inside the window is a manual step: Device Hub
            has no documented way to be pointed at a UDID from the command line.
            """
        )

        @Flag(name: .long, help: "Emit the resolved app as JSON ({ name, path, opened }).")
        var json = false

        @Flag(name: .long, help: "Only resolve and report the app; do not open it.")
        var printOnly = false

        func run() throws {
            let developerDir = SPSimBridge.defaultDeveloperDir()
            guard let app = SimulatorUIApp.resolve(developerDir: developerDir) else {
                throw ValidationError(
                    "No Device Hub in the active Xcode (\(developerDir)). Looked for: "
                    + "\(SimulatorUIApp.deviceHub(developerDir: developerDir).path). Headless driving is unaffected."
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
