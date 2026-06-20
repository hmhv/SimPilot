// Capture.swift
//
// `sipi record-video` and `sipi list-simulators` — the capture + enumeration
// surface the skill docs call.
//
//   record-video    Wraps `xcrun simctl io <udid> recordVideo --codec h264
//                   --force <path>` as a background process. Returns once simctl
//                   reports "Recording started", then waits for SIGINT and
//                   finalizes the recording with a clean SIGINT to the child
//                   (matches the `axe record-video … &; kill -INT` pattern,
//                   run.md:193).
//   list-simulators Native device enumeration. `--format axe` emits the
//                   pipe-table that run.md's `awk -F'|'` expects so the skill
//                   keeps working until it migrates to `simctl list devices`.

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

        func run() throws {
            // Arm the SIGINT latch BEFORE recordVideo, which blocks up to ~10s
            // waiting for "Recording started". The skill backgrounds this command
            // and may `kill -INT` during that startup window; without the custom
            // disposition in place, the default SIGINT would kill sipi here,
            // orphaning the simctl child and leaving an unfinalized container.
            RecordVideoSignal.shared.install()

            // Start recording; gate on simctl's "Recording started" stderr line so
            // the caller does not race the start of capture (§6.8).
            let recording = try SimShell.recordVideo(udid: udid, outputPath: path)

            // Wait for the SIGINT, then forward a clean SIGINT to the simctl child
            // so it finalizes the container (moov atom) before we exit.
            RecordVideoSignal.shared.wait()

            let status = recording.stop()
            emitError("[sipi] recording finalized: \(path)")
            if status != 0 {
                throw ExitCode(status)
            }
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
    private var source: DispatchSourceSignal?

    func install() {
        // Ignore the default SIGINT disposition so the DispatchSourceSignal can
        // observe it instead of the process being terminated.
        signal(SIGINT, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
        source.setEventHandler { [weak self] in
            self?.semaphore.signal()
        }
        source.resume()
        self.source = source
    }

    func wait() {
        semaphore.wait()
    }
}

// MARK: - list-simulators

extension Sipi {
    struct ListSimulators: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list-simulators",
            abstract: "List simulators. Default is JSON; --format axe emits the pipe-table run.md awk consumes."
        )

        enum Format: String, ExpressibleByArgument {
            case json
            case axe
        }

        @Option(name: .long, help: "Output format: json (default) or axe (pipe-table).")
        var format: Format = .json

        func run() throws {
            let driver = NativeDriver()
            let devices = try driver.devices()

            switch format {
            case .json:
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

            case .axe:
                // Match `axe list-simulators` byte shape so run.md's
                //   `awk -F'|' '{print $2}'` (device name) keeps working:
                //   <udid> | <name> | <state> | <model> | OS '<runtime>'
                // with a trailing space after the closing quote.
                var lines: [String] = []
                for d in devices {
                    let model = d.model ?? ""
                    let runtime = d.runtime ?? ""
                    lines.append("\(d.udid) | \(d.name) | \(d.stateString) | \(model) | OS '\(runtime)' ")
                }
                let output = lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
                FileHandle.standardOutput.write(Data(output.utf8))
            }
        }
    }
}
