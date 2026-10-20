// FoldState.swift
//
// `sipi fold-state <udid>` — which of the device's screens is lit, and what it
// measures. Xcode 27.2 offers no way to read the hinge angle itself.
//
// This reads; `sipi fold` writes. The read is devicectl's display report; the
// write goes through a guest-side helper (see SimShell's HingeControl), because
// simctl has no verb and CoreSimulator carries no hinge symbol.
//
// Why that is worth a command: on a foldable every other reading depends on the
// answer. A capture of the dark screen is a black PNG, an accessibility tree
// read from the wrong screen describes something nobody is looking at, and a
// 466x678 tree where 669x951 was expected looks like a layout bug rather than a
// shut device.

import ArgumentParser
import Foundation
import SimCore
import SimNative
import SimShell

extension Sipi {
    struct FoldState: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "fold-state",
            abstract: "Report which built-in screen is lit on a foldable (read only)."
        )

        @Argument(help: "Simulator UDID.")
        var udid: String

        func run() throws {
            let displays = try DeviceCtl.displays(udid: udid)
            guard !displays.isEmpty else {
                throw ValidationError(
                    "Cannot read this device's screens. `devicectl device info displays` answered "
                    + "nothing usable — it only speaks to simulators from Xcode 27 on, and only to "
                    + "booted ones."
                )
            }

            let roles = DisplaySelection.roles(displays)
            let active = DisplaySelection.active(displays)
            let foldable = displays.count == 2

            var object: [String: Any] = [
                "foldable": foldable,
                "folded": DisplaySelection.isFolded(displays) as Any? ?? NSNull(),
                "displays": displays.map { display -> [String: Any] in
                    // `active` here is the resolved answer, not devicectl's raw
                    // flag — which a single-screen device does not carry at all.
                    let lit = display.screenID == active?.screenID
                    var entry: [String: Any] = [
                        "id": display.screenID,
                        "name": display.name,
                        "role": (roles[display.screenID] ?? .screen).rawValue,
                        "active": lit,
                        "primary": display.primary,
                        "pixelSize": [display.pixelWidth, display.pixelHeight],
                        "pointSize": [display.pointWidth, display.pointHeight],
                        "pointScale": display.pointScale
                    ]
                    // Only the lit screen's rotation means anything: a screen that
                    // is off keeps reporting whatever it last showed.
                    if let rotation = display.rotation, lit {
                        entry["rotation"] = rotation
                    }
                    return entry
                }
            ]

            if let active {
                object["activeDisplay"] = active.screenID
                // The orientation READ is screen-aware now, so this is the lit
                // screen's own orientation and the space describe-ui frames and
                // tap points are in.
                if let orientation = try? NativeDriver().uiOrientation(udid) {
                    object["orientation"] = orientation.name
                }
            } else {
                object["activeDisplay"] = NSNull()
            }

            let data = try JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys]
            )
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }
}
