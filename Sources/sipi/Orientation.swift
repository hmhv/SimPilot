// Orientation.swift
//
// `sipi orientation <udid>` — native orientation READ via SimulatorKit
// (SimDeviceScreen.uiOrientation, UInt32 1...4).
//
// READ (default, `sipi orientation <udid>`): emits the lowercase orientation name
// on stdout (portrait | portrait-upside-down | landscape-left | landscape-right);
// `--json` emits { "orientation": <name>, "raw": <1...4> } for machine consumers.
// NativeDriver coordinate math depends on the READ contract.
//
// SET (`sipi orientation <udid> --set <name>`): rotates the device. The native
// PurpleEvent SET is tried first (headless, locale-independent, covers
// UIDeviceOrientation 1...4), then `devicectl device orientation set`, which is
// headless too and is the only supported way to express face-up / face-down now
// that Xcode 27 removed Simulator.app. The osascript menu path remains as a
// last resort for Xcode 26 and earlier.

import ArgumentParser
import Foundation
import SimCore
import SimNative
import SimShell

extension Sipi {
    struct Orientation: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "orientation",
            abstract: "Read or set the simulator's physical UI orientation (native SET, devicectl fallback)."
        )

        @Argument(help: "Simulator UDID.")
        var udid: String

        @Flag(name: .long, help: "Emit the orientation as JSON ({ orientation, raw }).")
        var json = false

        @Option(name: .long, help: "Set the orientation instead of reading it: \(OrientationSetName.acceptedNames).")
        var set: String?

        @Flag(
            name: .long,
            help: """
            Also report the physical orientation via devicectl, which detects the \
            face-up / face-down states SimulatorKit cannot express. Costs one \
            process spawn.
            """
        )
        var physical = false

        func run() throws {
            let driver = NativeDriver()

            if let set {
                guard let name = OrientationSetName(set) else {
                    throw ValidationError("Unknown orientation '\(set)'. Valid: \(OrientationSetName.acceptedNames).")
                }
                try driver.setOrientation(name, udid: udid)
                print("ok")
                return
            }

            let orientation = try driver.uiOrientation(udid)
            let name = orientationName(orientation)

            // The plain (non-JSON) READ contract stays exactly the four upright
            // names — NativeDriver's coordinate math and the skills both parse it.
            // `--physical` only ever adds keys to the JSON form.
            if physical && !json {
                throw ValidationError("--physical requires --json.")
            }

            if json {
                var object: [String: Any] = [
                    "orientation": name,
                    "raw": orientation.rawValue
                ]
                if physical {
                    let reading = DeviceCtl.isSimulatorCapable() ? try? DeviceCtl.orientation(udid: udid) : nil
                    // NSNull, not an omitted key: "devicectl says upright" and
                    // "devicectl could not be asked" must not look identical.
                    object["flat"] = reading?.flat ?? NSNull()
                    object["physical"] = reading?.deviceOrientation ?? NSNull()
                    object["locked"] = reading?.isLocked ?? NSNull()
                }
                let data = try JSONSerialization.data(
                    withJSONObject: object,
                    options: [.prettyPrinted]
                )
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            } else {
                print(name)
            }
        }

        /// Stable lowercase name for an orientation. Matches the names the
        /// SimBridge READ emits and the orientation SET path accepts.
        private func orientationName(_ orientation: UIOrientation) -> String {
            switch orientation {
            case .portrait: return "portrait"
            case .portraitUpsideDown: return "portrait-upside-down"
            case .landscapeLeft: return "landscape-left"
            case .landscapeRight: return "landscape-right"
            }
        }
    }
}
