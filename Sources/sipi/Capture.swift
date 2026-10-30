// Capture.swift
//
// `sipi record-video` and `sipi list-simulators` — the capture + enumeration
// surface the skill docs call.
//
//   record-video    Wraps `xcrun simctl io <udid> recordVideo --codec h264
//                   --force <path>` as a background process. Returns once simctl
//                   reports "Recording started", then waits for SIGINT and
//                   finalizes the recording with a clean SIGINT to the child.
//   list-simulators Native device enumeration as JSON.

import ArgumentParser
import Darwin
import Foundation
import SimCore
import SimNative
import SimShell

// MARK: - record-video

extension Sipi {
    struct RecordVideo: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "record-video",
            abstract: "Record the simulator display to a video file. Runs until SIGINT (kill -INT) finalizes it."
        )

        @Argument(help: "Simulator UDID.")
        var udid: String

        @Argument(help: "Output video path (e.g. recording.mp4). simctl writes an H.264 QuickTime container.")
        var path: String

        @Option(
            name: .long,
            help: """
            Which built-in screen to record: \(DisplaySelection.selectorSyntax). \
            Defaults to whichever screen the device is lighting. Only a foldable \
            (iPhone Duo) has more than one, and simctl refuses to pick one there.
            """
        )
        var display: String = "active"

        func validate() throws {
            if DisplaySelection.parseSelector(display) == nil {
                throw ValidationError("Unknown --display '\(display)'. Valid: \(DisplaySelection.selectorSyntax).")
            }
        }

        func run() throws {
            // Arm the SIGINT latch BEFORE recordVideo, which blocks up to ~10s
            // waiting for "Recording started". The skill backgrounds this command
            // and may `kill -INT` during that startup window; without the custom
            // disposition in place, the default SIGINT would kill sipi here,
            // orphaning the simctl child and leaving an unfinalized container.
            RecordVideoSignal.shared.install()

            // Resolve the screen before recording starts. nil means the screens
            // could not be read at all (a device still coming up), in
            // which case simctl's own default is the best available answer — and
            // is correct for every device with one screen.
            let selector = DisplaySelection.parseSelector(display) ?? .active
            let screen = try DisplayResolver.resolve(selector, udid: udid)

            // Start recording; gate on simctl's "Recording started" stderr line so
            // the caller does not race the start of capture (§6.8).
            let recording = try SimShell.recordVideo(
                udid: udid,
                outputPath: path,
                screenID: screen?.screenID
            )

            // Wait for the SIGINT, then forward a clean SIGINT to the simctl child
            // so it finalizes the container (moov atom) before we exit.
            while !RecordVideoSignal.shared.wait(seconds: 1) {
                if !recording.isRunning { break }
            }

            let status = recording.stop()
            guard status == 0 else {
                emitError("[sipi] recording ended with status \(status): \(path) may be incomplete")
                throw ExitCode(status)
            }
            emitError("[sipi] recording finalized: \(path)")
        }
    }
}

/// A one-shot SIGINT latch for `record-video`. The command installs a SIGINT
/// handler that flips a flag and signals a semaphore so the main thread can wake
/// from `wait()` and finalize the recording, rather than letting the default
/// SIGINT disposition kill the process (which would leave the video container
/// unfinalized).
private final class RecordVideoSignal: @unchecked Sendable {
    static let shared = RecordVideoSignal()
    private let semaphore = DispatchSemaphore(value: 0)

    private var sources: [DispatchSourceSignal] = []

    /// SIGTERM too: a plain `kill` or a task timeout would otherwise leave the
    /// simctl child recording and the container unfinalized.
    func install() {
        for number in [SIGINT, SIGTERM] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler { [weak self] in
                self?.semaphore.signal()
            }
            source.resume()
            sources.append(source)
        }
    }

    /// True when a signal arrived within `seconds`.
    func wait(seconds: Double) -> Bool {
        semaphore.wait(timeout: .now() + seconds) == .success
    }
}

// MARK: - list-simulators

extension Sipi {
    struct ListSimulators: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list-simulators",
            abstract: "List simulators as JSON."
        )

        func run() throws {
            let devices = try NativeDriver().devices()
            let array: [[String: Any]] = devices.map { d in
                [
                    "udid": d.udid,
                    "name": d.name,
                    "state": d.stateString,
                    "booted": d.booted,
                    "model": d.model ?? "",
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
