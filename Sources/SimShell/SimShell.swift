// SimShell.swift
//
// Typed Process() wrappers over the public `xcrun simctl` for app/file/
// lifecycle facets that never touch private frameworks. Pure Foundation: no
// SimBridge, no private frameworks.

import Foundation

public enum SimShellError: Error, CustomStringConvertible {
    case launchFailed(String)
    case nonZeroExit(command: String, code: Int32, stderr: String)
    case notBooted(udid: String)

    public var description: String {
        switch self {
        case .launchFailed(let message):
            return "failed to launch process: \(message)"
        case .nonZeroExit(let command, let code, let stderr):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "`\(command)` exited \(code)\(trimmed.isEmpty ? "" : ": \(trimmed)")"
        case .notBooted(let udid):
            return "simulator \(udid) is not booted; boot it before this operation"
        }
    }
}

/// Result of running a child process.
public struct SimShellResult: Sendable {
    public var stdout: String
    public var stderr: String
    public var exitCode: Int32

    public var succeeded: Bool { exitCode == 0 }
}

public enum SimShell {
    /// Run `xcrun simctl` with the given arguments and capture output. Optionally
    /// writes `stdin` to the child's standard input first. Throws on launch
    /// failure; a non-zero exit is reported via `SimShellResult.exitCode` so
    /// callers can decide how to handle it.
    private static func run(_ args: [String], stdin: Data? = nil) throws -> SimShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl"] + args

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let inPipe: Pipe?
        if stdin != nil {
            let pipe = Pipe()
            process.standardInput = pipe
            inPipe = pipe
        } else {
            inPipe = nil
        }

        do {
            try process.run()
        } catch {
            throw SimShellError.launchFailed(error.localizedDescription)
        }

        if let inPipe, let stdin {
            inPipe.fileHandleForWriting.write(stdin)
            inPipe.fileHandleForWriting.closeFile()
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return SimShellResult(
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }

    /// Run `xcrun simctl <args>` and throw `SimShellError.nonZeroExit` on a
    /// non-zero exit. Returns the captured stdout for callers that want it.
    @discardableResult
    private static func runChecked(_ args: [String], stdin: Data? = nil) throws -> String {
        let result = try run(args, stdin: stdin)
        guard result.succeeded else {
            throw SimShellError.nonZeroExit(
                command: "xcrun simctl " + args.joined(separator: " "),
                code: result.exitCode,
                stderr: result.stderr
            )
        }
        return result.stdout
    }

    // MARK: - Boot-before-use ordering

    /// Whether `udid` is currently booted. Pure parse over
    /// `simctl list devices booted`; never throws on a missing device.
    public static func isBooted(_ udid: String) -> Bool {
        (try? bootedDevices().contains { $0.udid == udid }) ?? false
    }

    /// Ensure `udid` is booted before an operation that requires it. Throws
    /// `SimShellError.notBooted` otherwise. The setup/capture wrappers that need
    /// a live device call this first so callers get an actionable error instead
    /// of an opaque simctl failure (boot-before-use ordering, §6.7).
    public static func requireBooted(_ udid: String) throws {
        guard isBooted(udid) else {
            throw SimShellError.notBooted(udid: udid)
        }
    }

    // MARK: - Lifecycle (boot/shutdown/erase)

    /// Boot `udid`. No-op if already booted (simctl reports a benign error that
    /// is swallowed when the device is in fact booted).
    public static func boot(udid: String) throws {
        if isBooted(udid) { return }
        try runChecked(["boot", udid])
    }

    /// Shut down `udid`.
    public static func shutdown(udid: String) throws {
        try runChecked(["shutdown", udid])
    }

    /// Erase `udid` back to a clean state. The device must be shut down first;
    /// callers that want a clean booted device should shutdown -> erase -> boot.
    public static func erase(udid: String) throws {
        try runChecked(["erase", udid])
    }

    // MARK: - App lifecycle (install/launch/terminate/uninstall)

    /// Install the app bundle at `path` onto `udid` (must be booted).
    public static func install(udid: String, appPath: String) throws {
        try requireBooted(udid)
        try runChecked(["install", udid, appPath])
    }

    /// Launch `bundleID` on `udid` (must be booted). Returns simctl's stdout
    /// (typically `<bundleID>: <pid>`).
    @discardableResult
    public static func launch(udid: String, bundleID: String, arguments: [String] = []) throws -> String {
        try requireBooted(udid)
        return try runChecked(["launch", udid, bundleID] + arguments)
    }

    /// Terminate `bundleID` on `udid` (must be booted).
    public static func terminate(udid: String, bundleID: String) throws {
        try requireBooted(udid)
        try runChecked(["terminate", udid, bundleID])
    }

    /// Uninstall `bundleID` from `udid` (must be booted).
    public static func uninstall(udid: String, bundleID: String) throws {
        try requireBooted(udid)
        try runChecked(["uninstall", udid, bundleID])
    }

    // MARK: - Setup (addmedia / privacy / openurl / ui appearance / status_bar)

    /// Add media files (photos/videos) to `udid`'s library (must be booted).
    public static func addMedia(udid: String, paths: [String]) throws {
        try requireBooted(udid)
        try runChecked(["addmedia", udid] + paths)
    }

    /// Grant a privacy permission for `bundleID` on `udid` (must be booted).
    /// `service` is a simctl privacy service such as `photos`, `camera`,
    /// `location`, `contacts`.
    public static func grantPrivacy(udid: String, service: String, bundleID: String) throws {
        try requireBooted(udid)
        try runChecked(["privacy", udid, "grant", service, bundleID])
    }

    /// Open `url` on `udid` (must be booted) — deep links, https, etc.
    public static func openURL(udid: String, url: String) throws {
        try requireBooted(udid)
        try runChecked(["openurl", udid, url])
    }

    /// Set the UI appearance (`light` / `dark`) on `udid`. Note: `appearance` is
    /// a sub-option of `simctl ui`, not a top-level subcommand (§6.7).
    public static func setAppearance(udid: String, appearance: String) throws {
        try requireBooted(udid)
        try runChecked(["ui", udid, "appearance", appearance])
    }

    /// Read the current UI appearance (`light` / `dark`) of `udid` via
    /// `simctl ui <udid> appearance`.
    public static func appearance(udid: String) throws -> String {
        try requireBooted(udid)
        return try runChecked(["ui", udid, "appearance"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Override the status bar on `udid` (must be booted). `arguments` are the
    /// raw `simctl status_bar <udid> override` flags (e.g. `--time`, `--batteryLevel`).
    public static func statusBarOverride(udid: String, arguments: [String]) throws {
        try requireBooted(udid)
        try runChecked(["status_bar", udid, "override"] + arguments)
    }

    /// Clear any status bar overrides on `udid` (must be booted).
    public static func statusBarClear(udid: String) throws {
        try requireBooted(udid)
        try runChecked(["status_bar", udid, "clear"])
    }

    // MARK: - Pasteboard (non-US `type` paste path)

    /// Read the simulator's pasteboard via `simctl pbpaste`. Returns the raw
    /// contents (may be empty). Throws on a non-zero exit so the caller can
    /// decide whether a save/restore is feasible.
    public static func pbpaste(udid: String) throws -> String {
        let result = try run(["pbpaste", udid])
        guard result.succeeded else {
            throw SimShellError.nonZeroExit(
                command: "xcrun simctl pbpaste \(udid)",
                code: result.exitCode,
                stderr: result.stderr
            )
        }
        return result.stdout
    }

    /// Write `text` onto the simulator's pasteboard via `simctl pbcopy`. This
    /// CLOBBERS the simulator pasteboard; callers that care should save the prior
    /// contents with `pbpaste` and restore them afterward.
    public static func pbcopy(_ text: String, udid: String) throws {
        let result = try run(["pbcopy", udid], stdin: Data(text.utf8))
        guard result.succeeded else {
            throw SimShellError.nonZeroExit(
                command: "xcrun simctl pbcopy \(udid)",
                code: result.exitCode,
                stderr: result.stderr
            )
        }
    }

    /// One simulator device parsed from `simctl list devices`.
    public struct BootedDevice: Sendable {
        public var udid: String
        public var name: String
        public var runtime: String
    }

    /// Booted simulators, parsed from `simctl list devices booted`.
    /// The text output groups devices under `-- <runtime> --` headers and lists
    /// each as `    <name> (<udid>) (Booted)`.
    public static func bootedDevices() throws -> [BootedDevice] {
        let result = try run(["list", "devices", "booted"])
        guard result.succeeded else {
            throw SimShellError.nonZeroExit(
                command: "xcrun simctl list devices booted",
                code: result.exitCode,
                stderr: result.stderr
            )
        }

        var devices: [BootedDevice] = []
        var runtime = ""
        for rawLine in result.stdout.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("--") && line.hasSuffix("--") {
                runtime = line
                    .trimmingCharacters(in: CharacterSet(charactersIn: "- "))
                continue
            }
            // Expect: <name> (<udid>) (Booted)
            guard let last = line.range(of: " (", options: .backwards) else { continue }
            guard let open = line.range(of: " (", range: line.startIndex..<last.lowerBound)
                ?? line.range(of: "(", range: line.startIndex..<last.lowerBound) else { continue }
            let name = String(line[line.startIndex..<open.lowerBound])
                .trimmingCharacters(in: .whitespaces)
            let afterOpen = line[open.upperBound...]
            guard let close = afterOpen.range(of: ")") else { continue }
            let udid = String(afterOpen[afterOpen.startIndex..<close.lowerBound])
            guard !udid.isEmpty, !name.isEmpty else { continue }
            devices.append(BootedDevice(udid: udid, name: name, runtime: runtime))
        }
        return devices
    }

    // MARK: - Background processes (record-video, log stream)

    /// A long-running `xcrun simctl` child (e.g. `io recordVideo`,
    /// `spawn log stream`). The process keeps running until `stop()` sends SIGINT
    /// (so the child can finalize cleanly — matches the `axe record-video … &;
    /// kill -INT` pattern in run.md:193). The child's stdout/stderr are inherited
    /// from the parent so its output streams through unchanged.
    public final class BackgroundProcess {
        private let process: Process
        public let command: String

        fileprivate init(process: Process, command: String) {
            self.process = process
            self.command = command
        }

        /// PID of the running child.
        public var processIdentifier: Int32 { process.processIdentifier }

        /// Whether the child is still running.
        public var isRunning: Bool { process.isRunning }

        /// Send SIGINT (equivalent to `kill -INT`) so the child finalizes its
        /// output (e.g. flushes the video container's moov atom), then wait for
        /// it to exit. Returns the child's exit status.
        @discardableResult
        public func stop() -> Int32 {
            if process.isRunning {
                kill(process.processIdentifier, SIGINT)
                process.waitUntilExit()
            }
            return process.terminationStatus
        }

        /// Block until the child exits on its own. Returns the exit status.
        @discardableResult
        public func waitUntilExit() -> Int32 {
            process.waitUntilExit()
            return process.terminationStatus
        }
    }

    /// Start `xcrun simctl io <udid> recordVideo --codec h264 --force <path>` as a
    /// background process and return once recording has actually begun. simctl
    /// prints "Recording started" to stderr once the capture pipeline is live;
    /// this method tees stderr so it can gate on that line (with a timeout) before
    /// returning, so callers do not race the start of recording. Finalize the
    /// recording with `BackgroundProcess.stop()` (SIGINT), matching the
    /// `axe record-video … &; kill -INT` pattern (run.md:193). The output is
    /// written to `path` as requested; note simctl writes a QuickTime-branded
    /// container even for a `.mp4` name (acceptable — §6.8).
    public static func recordVideo(
        udid: String,
        outputPath: String,
        startTimeout: TimeInterval = 10
    ) throws -> BackgroundProcess {
        try requireBooted(udid)

        let args = ["simctl", "io", udid, "recordVideo", "--codec", "h264", "--force", outputPath]
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = args

        // Tee stderr: capture it so we can gate on "Recording started", while
        // still forwarding each chunk to the parent's stderr so diagnostics show.
        let errPipe = Pipe()
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            throw SimShellError.launchFailed(error.localizedDescription)
        }

        let command = "xcrun " + args.joined(separator: " ")
        let handle = errPipe.fileHandleForReading
        let deadline = Date().addingTimeInterval(startTimeout)
        var started = false
        var seen = ""

        // Time-bound the wait so `startTimeout` fires even if the child stays
        // alive with stderr open but never prints "Recording started". We make
        // the fd non-blocking and read it with POSIX read(2) directly:
        // FileHandle.availableData RAISES an NSException on EAGAIN under a
        // non-blocking fd, so it cannot be used here.
        let fd = handle.fileDescriptor
        let savedFlags = fcntl(fd, F_GETFL)
        if savedFlags != -1 {
            _ = fcntl(fd, F_SETFL, savedFlags | O_NONBLOCK)
        }

        // Read stderr until "Recording started" appears, the child exits, or the
        // timeout elapses. Each chunk is forwarded to the parent's stderr.
        var buf = [UInt8](repeating: 0, count: 4096)
        while Date() < deadline {
            let n = buf.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if n > 0 {
                let chunk = Data(buf[0..<n])
                FileHandle.standardError.write(chunk)
                seen += String(decoding: chunk, as: UTF8.self)
                if seen.contains("Recording started") {
                    started = true
                    break
                }
                continue
            }
            if n == 0 {
                // EOF — the child closed stderr (it exited or failed to start).
                break
            }
            // n < 0: no data yet (EAGAIN/EWOULDBLOCK) or interrupted (EINTR). On
            // any other error, stop. Otherwise, if the child has exited, stop;
            // else wait briefly and re-check the deadline so the timeout fires.
            if errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR { break }
            if !process.isRunning { break }
            Thread.sleep(forTimeInterval: 0.05)
        }

        // Restore the fd's original blocking mode for any later consumer.
        if savedFlags != -1 {
            _ = fcntl(fd, F_SETFL, savedFlags)
        }

        if !started {
            // Either the child exited early or never reported a start. Stop it and
            // report a launch failure with whatever stderr we gathered.
            if process.isRunning {
                kill(process.processIdentifier, SIGINT)
            }
            process.waitUntilExit()
            let trimmed = seen.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SimShellError.nonZeroExit(
                command: command,
                code: process.terminationStatus,
                stderr: trimmed.isEmpty ? "recording did not start within \(startTimeout)s" : trimmed
            )
        }

        return BackgroundProcess(process: process, command: command)
    }

    /// Start `xcrun simctl spawn <udid> log stream <extraArgs...>` as a background
    /// process whose stdout/stderr are inherited from the parent. Note: log
    /// streaming is `simctl spawn <dev> log stream`, NOT a `simctl log`
    /// subcommand (§6.7). Stop it with `BackgroundProcess.stop()`.
    public static func logStream(udid: String, extraArgs: [String] = []) throws -> BackgroundProcess {
        try requireBooted(udid)

        let args = ["simctl", "spawn", udid, "log", "stream"] + extraArgs
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = args

        do {
            try process.run()
        } catch {
            throw SimShellError.launchFailed(error.localizedDescription)
        }

        return BackgroundProcess(process: process, command: "xcrun " + args.joined(separator: " "))
    }
}
