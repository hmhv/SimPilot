// Button.swift
//
// `sipi button <udid> <name>` — press a hardware button via the native Indigo
// HID path (SPSimBridge.pressButton, exposed through NativeDriver.button). The
// capability already existed in the C core and NativeDriver; this just surfaces
// it on the umbrella CLI for AXe `button` parity.
//
// Valid names match the SimBridge pressButton handler and HardwareButton raw
// values: home | lock | side_button | app_switcher | siri | swipe_home.

import ArgumentParser
import Foundation
import SimCore
import SimNative

extension Sipi {
    struct Button: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "button",
            abstract: "Press a hardware button (home, lock, side_button, app_switcher, siri, swipe_home)."
        )

        @Argument(help: "Simulator UDID.")
        var udid: String

        @Argument(help: "Button: home | lock | side_button | app_switcher | siri | swipe_home.")
        var name: String

        func run() throws {
            guard let button = HardwareButton(rawValue: name) else {
                throw ValidationError(
                    "Unknown button '\(name)'. Valid: home, lock, side_button, app_switcher, siri, swipe_home."
                )
            }
            let driver = NativeDriver()
            try driver.button(button, udid: udid)
            print("ok")
        }
    }
}
