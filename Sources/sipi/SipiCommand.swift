// SipiCommand.swift
//
// `sipi` — the umbrella CLI and sole native simulator driver for the package.
// It provides the perception, input, capture, lifecycle, and report subcommands
// the `sipi-*` skills drive.

import ArgumentParser
import Foundation
import SimCore
import SimNative
import SimShell
import SimBridge

/// The sipi version. Keep in sync with the repo-root VERSION file.
let sipiVersion = "1.0.0"

@main
struct Sipi: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sipi",
        abstract: "Native simulator driver CLI.",
        version: sipiVersion,
        subcommands: [
            Devices.self,
            ListSimulators.self,
            DescribeUI.self,
            DescribePoint.self,
            Tap.self,
            TypeText.self,
            Key.self,
            KeySequence.self,
            KeyCombo.self,
            Swipe.self,
            Touch.self,
            Drag.self,
            Gesture.self,
            SliderSet.self,
            Button.self,
            Orientation.self,
            MultiTouch.self,
            Crown.self,
            Screenshot.self,
            RecordVideo.self,
            Report.self,
            VerifyReport.self,
            Validate.self,
            Doctor.self,
            Version.self,
            Setup.self,
            Update.self,
            Uninstall.self
        ]
    )
}

// MARK: - version

extension Sipi {
    struct Version: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "version",
            abstract: "Print the sipi version (use --json for machine-readable output)."
        )

        @Flag(name: .long, help: "Emit the version as JSON ({ version }).")
        var json = false

        func run() throws {
            if json {
                let data = try JSONSerialization.data(
                    withJSONObject: ["version": sipiVersion],
                    options: [.prettyPrinted]
                )
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            } else {
                print(sipiVersion)
            }
        }
    }
}

// MARK: - devices

extension Sipi {
    struct Devices: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "devices",
            abstract: "List simulators as JSON."
        )

        func run() throws {
            let driver = NativeDriver()
            let devices = try driver.devices()
            let array: [[String: Any]] = devices.map { d in
                [
                    "udid": d.udid,
                    "name": d.name,
                    "state": d.stateString,
                    "booted": d.booted,
                    "runtime": d.runtime ?? ""
                ]
            }
            let data = try JSONSerialization.data(
                withJSONObject: array,
                options: [.prettyPrinted]
            )
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }
}

// MARK: - screenshot

extension Sipi {
    struct Screenshot: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "screenshot",
            abstract: "Capture a PNG of the simulator framebuffer."
        )

        @Argument(help: "Simulator UDID.")
        var udid: String

        @Argument(help: "Destination PNG path.")
        var path: String

        func run() throws {
            let driver = NativeDriver()
            try driver.screenshot(to: URL(fileURLWithPath: path), udid: udid)
            print(path)
        }
    }
}
