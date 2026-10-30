// RepairInput.swift
//
// `sipi repair-input <udid>` — reconnect a simulator's touch and keyboard input
// after Xcode 27's Device Hub has taken it over. SimShell's InputRepair explains
// the state it reads and what the repair does.

import ArgumentParser
import Foundation
import SimCore
import SimNative
import SimShell

extension Sipi {
    struct RepairInput: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "repair-input",
            abstract: "Reconnect touch and keyboard input that Device Hub has taken over (restarts SpringBoard).",
            discussion: """
            Device Hub can leave a simulator ignoring sipi's taps and keys while every \
            command still reports ok; `sipi doctor` says when that has happened. This \
            clears Device Hub's hold and restarts backboardd, which restarts SpringBoard \
            and CLOSES EVERY RUNNING APP — relaunch the app afterwards. When input is not \
            held, it changes nothing.
            """
        )

        @Argument(help: "Simulator UDID.")
        var udid: String

        func run() throws {
            try SimShell.requireBooted(udid)
            let innerWasLit = DuoScreens.isInnerLit(DisplayResolver.displays(udid: udid))
            if try SimShell.repairDeviceHubInput(udid: udid) {
                print("Input repaired. SpringBoard restarted and running apps were closed; relaunch the app.")
                if innerWasLit {
                    print("This Duo now shows its cover although it is still open; run `sipi fold \(udid) --closed` "
                        + "then `--open` to light the inner screen again.")
                }
            } else {
                print("Input is not held; nothing changed.")
            }
        }
    }
}
