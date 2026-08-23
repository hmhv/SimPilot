// SimShell.swift
//
// Typed Process() wrappers over the public `xcrun simctl` for app/file/
// lifecycle facets that never touch private frameworks. Pure Foundation: no
// SimBridge, no private frameworks.

import Foundation
import SimCore

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
    private static func run(
        _ args: [String],
        stdin: Data? = nil,
        environment: [String: String] = [:]
    ) throws -> SimShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl"] + args
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }

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
    private static func runChecked(
        _ args: [String],
        stdin: Data? = nil,
        environment: [String: String] = [:]
    ) throws -> String {
        let result = try run(args, stdin: stdin, environment: environment)
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
    public static func launch(
        udid: String,
        bundleID: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        terminateRunning: Bool = false
    ) throws -> String {
        try requireBooted(udid)
        let childEnvironment = Dictionary(uniqueKeysWithValues: environment.map {
            ("SIMCTL_CHILD_" + $0.key, $0.value)
        })
        let options = terminateRunning ? ["--terminate-running-process"] : []
        return try runChecked(
            ["launch"] + options + [udid, bundleID] + arguments,
            environment: childEnvironment
        )
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

    /// Revoke a privacy permission for `bundleID` on `udid`.
    public static func revokePrivacy(udid: String, service: String, bundleID: String) throws {
        try requireBooted(udid)
        try runChecked(["privacy", udid, "revoke", service, bundleID])
    }

    /// Reset a privacy permission. `bundleID` is optional only for reset, matching simctl.
    public static func resetPrivacy(udid: String, service: String, bundleID: String? = nil) throws {
        try requireBooted(udid)
        var args = ["privacy", udid, "reset", service]
        if let bundleID, !bundleID.isEmpty { args.append(bundleID) }
        try runChecked(args)
    }

    /// Open `url` on `udid` (must be booted) — deep links, https, etc.
    public static func openURL(udid: String, url: String) throws {
        try requireBooted(udid)
        try runChecked(["openurl", udid, url])
    }

    /// Send an inline APNs JSON payload to an installed simulator app.
    public static func push(udid: String, bundleID: String, payload: Data) throws {
        try requireBooted(udid)
        try runChecked(["push", udid, bundleID, "-"], stdin: payload)
    }

    /// Path to an installed app's `.app` bundle on `udid` via
    /// `simctl get_app_container <udid> <bundle-id> app`. Returns nil when the app
    /// is not installed, the device is not booted, or simctl cannot resolve the
    /// container — callers use this for advisory inspection, so absence must not
    /// be fatal.
    public static func appBundlePath(udid: String, bundleID: String) -> String? {
        try? appContainerPath(udid: udid, bundleID: bundleID, container: "app")
    }

    /// Resolve one installed app container through simctl. `container` is
    /// `app`, `data`, `groups`, or a concrete App Group identifier. The device
    /// must be booted.
    public static func appContainerPath(
        udid: String,
        bundleID: String,
        container: String
    ) throws -> String {
        try requireBooted(udid)
        let result = try run(["get_app_container", udid, bundleID, container])
        guard result.succeeded else {
            throw SimShellError.nonZeroExit(
                command: "xcrun simctl get_app_container \(udid) \(bundleID) \(container)",
                code: result.exitCode,
                stderr: result.stderr
            )
        }
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            throw SimShellError.launchFailed("simctl returned an empty container path")
        }
        return path
    }

    /// `UIBackgroundModes` declared by the installed app's `Info.plist`, or nil
    /// when the plist cannot be read. An installed app with no declaration yields
    /// an empty array, which is distinct from nil (unknown).
    public static func appBackgroundModes(udid: String, bundleID: String) -> [String]? {
        guard let bundlePath = appBundlePath(udid: udid, bundleID: bundleID) else { return nil }
        let plistPath = (bundlePath as NSString).appendingPathComponent("Info.plist")
        guard let data = FileManager.default.contents(atPath: plistPath),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil) as? [String: Any]
        else { return nil }
        guard let modes = plist["UIBackgroundModes"] else { return [] }
        return (modes as? [String]) ?? []
    }

    /// Set one simulated coordinate.
    public static func setLocation(udid: String, latitude: Double, longitude: Double) throws {
        try requireBooted(udid)
        let coordinate = String(format: "%.8f,%.8f", locale: Locale(identifier: "en_US_POSIX"), latitude, longitude)
        try runChecked(["location", udid, "set", coordinate])
    }

    /// Clear the active simulated location or route.
    public static func clearLocation(udid: String) throws {
        try requireBooted(udid)
        try runChecked(["location", udid, "clear"])
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

    /// Set the preferred content size category used by Dynamic Type.
    public static func setContentSize(udid: String, contentSize: String) throws {
        try requireBooted(udid)
        try runChecked(["ui", udid, "content_size", contentSize])
    }

    /// Read the preferred content size category.
    public static func contentSize(udid: String) throws -> String {
        try requireBooted(udid)
        return try runChecked(["ui", udid, "content_size"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Enable or disable Increase Contrast.
    public static func setIncreaseContrast(udid: String, enabled: Bool) throws {
        try requireBooted(udid)
        try runChecked(["ui", udid, "increase_contrast", enabled ? "enabled" : "disabled"])
    }

    /// Read Increase Contrast as `enabled`, `disabled`, `unsupported`, or `unknown`.
    public static func increaseContrast(udid: String) throws -> String {
        try requireBooted(udid)
        return try runChecked(["ui", udid, "increase_contrast"])
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

    /// Return simctl's current status-bar override description.
    public static func statusBarList(udid: String) throws -> String {
        try requireBooted(udid)
        return try runChecked(["status_bar", udid, "list"])
    }

    // MARK: - Pasteboard (`type` paste path)

    /// Read the simulator's pasteboard via `simctl pbpaste`. Returns the raw
    /// contents (may be empty). Throws on a non-zero exit so the caller can
    /// decide whether a save/restore is feasible. Retried on the same grounds as
    /// `pbcopy` below: a transient read failure here silently costs the user their
    /// clipboard, because the `type` paste path can only restore what it saved.
    public static func pbpaste(udid: String) throws -> String {
        try retrying(attempts: pasteboardAttempts, delay: pasteboardRetryDelay) {
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
    }

    /// Write `text` onto the simulator's pasteboard via `simctl pbcopy`. This
    /// CLOBBERS the simulator pasteboard (which is synced with the host
    /// pasteboard); callers that care should save the prior contents with
    /// `pbpaste` and restore them afterward.
    ///
    /// The pasteboard service is reached through the device's launchd, which
    /// answers with a non-zero exit while it is still coming up (a freshly booted
    /// device, a just-installed app, a device under load). Because the whole
    /// default `type` path depends on this call, a lone transient failure would
    /// fail an otherwise-good test step, so retry briefly before giving up. The
    /// final failure still carries simctl's stderr.
    public static func pbcopy(_ text: String, udid: String) throws {
        try retrying(attempts: pasteboardAttempts, delay: pasteboardRetryDelay) {
            let result = try run(["pbcopy", udid], stdin: Data(text.utf8))
            guard result.succeeded else {
                throw SimShellError.nonZeroExit(
                    command: "xcrun simctl pbcopy \(udid)",
                    code: result.exitCode,
                    stderr: result.stderr
                )
            }
        }
    }

    /// Total attempts (1 initial + retries) for the pasteboard calls.
    static let pasteboardAttempts = 3
    /// Gap between pasteboard attempts. Short enough to stay invisible in a step's
    /// timing, long enough to outlast a service that is mid-launch.
    static let pasteboardRetryDelay: TimeInterval = 0.15

    /// Run `body`, retrying up to `attempts` times while it throws. Returns the
    /// first success; rethrows the LAST error once the attempts are exhausted so
    /// the caller still reports the real failure (with stderr) rather than a
    /// synthesized one. Kept internal and closure-based so it is unit-testable
    /// without a simulator.
    static func retrying<T>(
        attempts: Int,
        delay: TimeInterval,
        _ body: () throws -> T
    ) throws -> T {
        precondition(attempts >= 1, "retrying requires at least one attempt")
        var lastError: Error?
        for attempt in 1...attempts {
            do {
                return try body()
            } catch {
                lastError = error
                if attempt < attempts, delay > 0 {
                    Thread.sleep(forTimeInterval: delay)
                }
            }
        }
        // Unreachable with attempts >= 1: the loop either returned or set lastError.
        throw lastError ?? SimShellError.launchFailed("retry loop produced no result")
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
        /// Handles this object owns for a child that writes to a file rather than
        /// inheriting our streams. The child holds its own descriptors, so these
        /// are closed once it exits instead of waiting for ARC to release us.
        private let ownedHandles: [FileHandle]
        private var handlesClosed = false
        public let command: String
        public let stderrPath: String?

        fileprivate init(
            process: Process,
            command: String,
            stderrPath: String? = nil,
            ownedHandles: [FileHandle] = []
        ) {
            self.process = process
            self.command = command
            self.stderrPath = stderrPath
            self.ownedHandles = ownedHandles
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
            if !handlesClosed {
                handlesClosed = true
                for handle in ownedHandles { try? handle.close() }
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

    /// Start a structured log stream and write it directly to an artifact file.
    /// This is harness plumbing, not a public simctl-alias command.
    public static func logStream(
        udid: String,
        outputPath: String,
        predicate: String? = nil,
        stderrPath: String? = nil
    ) throws -> BackgroundProcess {
        try requireBooted(udid)
        let outputURL = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: outputURL)
        let errorURL = URL(fileURLWithPath: stderrPath ?? outputPath + ".stderr.txt")
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        var args = ["simctl", "spawn", udid, "log", "stream", "--level", "debug", "--style", "ndjson"]
        if let predicate, !predicate.isEmpty {
            args += ["--predicate", predicate]
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = args
        process.standardOutput = handle
        process.standardError = errorHandle
        do {
            try process.run()
        } catch {
            try? handle.close()
            try? errorHandle.close()
            throw SimShellError.launchFailed(error.localizedDescription)
        }
        return BackgroundProcess(
            process: process,
            command: "xcrun " + args.joined(separator: " "),
            stderrPath: errorURL.path,
            ownedHandles: [handle, errorHandle]
        )
    }
}
