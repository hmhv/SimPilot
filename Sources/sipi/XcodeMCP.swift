// XcodeMCP.swift
//
// A narrow client for Xcode's own MCP device-interaction service, used as a
// fallback for the one thing sipi's driver cannot always do: deliver real
// keystrokes.
//
// A simulator can stop accepting the Indigo HID keyboard messages sipi injects.
// Measured on Xcode 27.0 beta 6: on such a device sipi builds and sends exactly
// the same messages as on a healthy one — the hardware-keyboard mode is enabled,
// the HID client resolves, every message is non-NULL — and the guest simply
// ignores them, while Xcode's `sender keyboard kbd` types into the same focused
// field. So the keystrokes are reaching a dead path rather than a dead device,
// and nothing on sipi's side of that path can fix it.
//
// Xcode's route also does not care about the guest's keyboard layout. sipi's
// per-key HID does: with a Japanese keyboard active, typing "hello" produces
// "へっぉ" and reports success.
//
// This is deliberately not a general wrapper. sipi keeps its own implementation
// of everything it already does; this covers only text entry, only when it is
// available, and its absence is never an error — the driver's own paths remain
// the default and `set-text` still needs no keyboard at all.
//
// Requires Xcode 27 or later with headless mode enabled
// (`sudo xcrun mcp-server enable`), and a one-time approval of this agent.

import Foundation

enum XcodeMCP {
    /// Why the service cannot be used, in the words the user needs to act on.
    enum Unavailable: Error, CustomStringConvertible {
        case toolMissing
        case notEnabled
        /// The service is there but did not answer in time — it stops answering
        /// while an approval prompt is waiting for a human.
        case notAnswering
        case notApproved(String)
        /// The approval prompt is up and Xcode is waiting for a human.
        case approvalPending
        case failed(String)

        var description: String {
            switch self {
            case .toolMissing:
                return "Xcode's MCP service is not present in the selected developer directory (it needs Xcode 27 or later)."
            case .notEnabled:
                return "Xcode's MCP service is not enabled. Run `sudo xcrun mcp-server enable`."
            case .notAnswering:
                return "Xcode's MCP service did not answer. It stops answering while an approval prompt is waiting — accept or dismiss it, then try again."
            case .notApproved(let detail):
                return "Xcode's MCP service has not approved this copy of sipi yet. Run `sipi xcode-mcp --approve <project>` once. (\(detail))"
            case .approvalPending:
                return "Xcode has recorded the approval request and is waiting for you to accept it — approve it from the Xcode MCP menu bar icon, or run `sudo xcrun mcp-server status` to find the request id and `sudo xcrun mcp-server approve <id> --always`. Then run this again."
            case .failed(let detail):
                return "Xcode's MCP service failed: \(detail)"
            }
        }

        /// See `XcodeMCP.isBeforeTyping`.
        var isBeforeTyping: Bool { XcodeMCP.isBeforeTyping(self) }
    }

    /// Whether this failure happened before any character could have reached the
    /// guest, and so is safe for the harness to retry.
    ///
    /// Only a failure of the typing command itself is ambiguous: the service may
    /// have delivered the text and failed afterwards, and a retried step would
    /// type it twice.
    static func isBeforeTyping(_ reason: Unavailable) -> Bool {
        switch reason {
        case .toolMissing, .notEnabled, .notAnswering, .notApproved, .approvalPending:
            return true
        case .failed(let detail):
            return !detail.hasPrefix("DeviceInteractionSynthesize")
        }
    }

    /// How much of the service is usable right now.
    enum Readiness {
        /// Enabled, and this binary is approved: the fallback will work.
        case ready
        /// Enabled, but this binary has not been approved. Everything is in
        /// place except one `sipi xcode-mcp --approve` run.
        case notApprovedYet
        case unavailable(Unavailable)
    }

    /// Whether the service is present and switched on. Cheap: reads the
    /// service's own status, and does not start it.
    ///
    /// Deliberately does NOT consider approval. This gates the fallback, and
    /// approval is read by parsing human-readable output — a parsing miss would
    /// silently switch the feature off, whereas actually attempting the call
    /// gets an authoritative answer from Xcode itself. Reporting uses
    /// `readiness` instead, where being wrong only costs a misleading line.
    static func availability(developerDir: String) -> Result<Void, Unavailable> {
        switch enabledStatus(developerDir: developerDir) {
        case .success: return .success(())
        case .failure(let reason): return .failure(reason)
        }
    }

    /// Availability plus whether THIS binary is approved — what `doctor` and
    /// `sipi xcode-mcp` report, so neither claims the fallback is available
    /// when the next call would be refused.
    static func readiness(developerDir: String) -> Readiness {
        switch enabledStatus(developerDir: developerDir) {
        case .failure(let reason):
            return .unavailable(reason)
        case .success(let status):
            return isApproved(in: status) ? .ready : .notApprovedYet
        }
    }

    /// The service's status output, once, or why it could not be read.
    private static func enabledStatus(developerDir: String) -> Result<String, Unavailable> {
        guard let path = toolPath(developerDir: developerDir),
              FileManager.default.isExecutableFile(atPath: path) else {
            return .failure(.toolMissing)
        }
        // `status` prints "Permission: enabled" only once headless mode is on.
        // It also prints a warning line and still exits 0 when the service is
        // wedged behind an approval prompt, so a nil here is a timeout.
        guard let status = capture(path, ["status"], timeout: 3) else {
            return .failure(.notAnswering)
        }
        guard status.contains("Permission: enabled") else { return .failure(.notEnabled) }
        return .success(status)
    }

    /// Ask Xcode's service to approve this copy of `sipi`.
    ///
    /// The service grants an agent access only when that agent opens or creates
    /// a project — that is the moment it shows the approval prompt — so there is
    /// no way to ask for approval on its own. `projectPath` is opened purely to
    /// raise the prompt, and closed again immediately; nothing in it is read or
    /// changed. Returns the workspace identifier Xcode assigned, for the caller
    /// to report.
    ///
    /// Approval is granted to this exact binary. Replacing `sipi` (an update, a
    /// rebuild) invalidates it and this has to be run once more.
    static func requestApproval(projectPath: String, developerDir: String) throws -> String {
        if case .failure(let reason) = availability(developerDir: developerDir) { throw reason }
        guard let bridge = bridgePath(developerDir: developerDir) else { throw Unavailable.toolMissing }
        if let server = toolPath(developerDir: developerDir) {
            _ = capture(server, ["start"])
        }

        let client = try Client(bridgePath: bridge, developerDir: developerDir)
        defer { client.close() }

        // Xcode may have opened the project even when the call ends in an error
        // (a pending approval is reported as one), so the close has to run either
        // way — leaving a workspace open is a side effect this command promised
        // not to have. The identifier is looked up rather than guessed: Close
        // takes the identifier Xcode assigned, not a path.
        defer {
            let listed = try? client.call("XcodeListWorkspaces", [:] as [String: Any], timeout: 30)
            let identifier = listed.flatMap { workspaceIdentifier(matching: projectPath, in: $0) }
            if let identifier {
                _ = try? client.call("XcodeCloseWorkspace", ["workspaceIdentifier": identifier], timeout: 60)
            }
        }

        let opened = try client.call("XcodeOpenWorkspace", ["path": projectPath], timeout: 300)
        let identifier = (try? JSONSerialization.jsonObject(with: Data(opened.utf8)) as? [String: Any])
            .flatMap { $0?["workspaceIdentifier"] as? String }

        // Opening the project is what RAISES the prompt; it does not mean the
        // prompt was accepted. Confirm the grant actually landed rather than
        // telling the user they are done when they are not — and poll for it,
        // because the service records the grant a moment after it answers the
        // call, so a single immediate check reports a failure that is about to
        // become a success.
        guard awaitApproval(developerDir: developerDir, timeout: 10) else {
            throw Unavailable.approvalPending
        }
        return identifier ?? opened
    }

    /// The identifier of the open workspace whose path matches `path`, from an
    /// `XcodeListWorkspaces` reply.
    ///
    /// That reply is plain text, one line per workspace, NOT JSON — unlike
    /// `XcodeOpenWorkspace`, which answers with a JSON object:
    ///
    ///     * workspaceIdentifier: workspace-18VxbuBVv2, workspacePath: /path/to/App.xcodeproj
    ///
    /// Paths are compared after resolving symlinks, because the service echoes
    /// `/tmp/...` where the caller passed `/private/tmp/...`.
    static func workspaceIdentifier(matching path: String, in reply: String) -> String? {
        let wanted = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
        for line in reply.split(separator: "\n") {
            guard let idRange = line.range(of: "workspaceIdentifier:"),
                  let pathRange = line.range(of: "workspacePath:") else { continue }
            let identifier = line[idRange.upperBound...]
                .prefix { $0 != "," }
                .trimmingCharacters(in: .whitespaces)
            let candidate = line[pathRange.upperBound...].trimmingCharacters(in: .whitespaces)
            guard !identifier.isEmpty, !candidate.isEmpty else { continue }
            if URL(fileURLWithPath: candidate).resolvingSymlinksInPath().standardizedFileURL.path == wanted {
                return identifier
            }
        }
        return nil
    }

    /// Poll until the service lists this executable as approved, or give up.
    private static func awaitApproval(developerDir: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if isApproved(developerDir: developerDir) { return true }
            usleep(500 * 1000)
        } while Date() < deadline
        return false
    }

    /// Whether the service currently grants this executable access.
    private static func isApproved(developerDir: String) -> Bool {
        guard let path = toolPath(developerDir: developerDir),
              let status = capture(path, ["status"], timeout: 5) else { return false }
        return isApproved(in: status)
    }

    /// Whether a `mcp-server status` listing grants this executable access.
    ///
    /// Reads only the "Permitted agents" section. The listing also names
    /// PENDING requests with the same executable path, and matching anywhere in
    /// the blob would report a request that is still waiting as a grant that
    /// already happened.
    static func isApproved(in status: String, executable: String? = Bundle.main.executablePath) -> Bool {
        guard let executable else { return false }

        // Headless mode can be enabled with --unsafe-always-allow-all-agents,
        // in which case there is no per-agent record and every agent is already
        // permitted.
        if status.contains("unsafe") && status.contains("allow") { return true }

        var inPermittedAgents = false
        for line in status.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(line)
            if !text.hasPrefix(" ") && text.contains(":") {
                inPermittedAgents = text.hasPrefix("Permitted agents")
                continue
            }
            if inPermittedAgents, text.contains(executable) { return true }
        }
        return false
    }

    /// Type `text` into whatever currently has keyboard focus on `udid`.
    ///
    /// Opens a device-interaction session, sends one keyboard command, and
    /// closes it. A session that is not bound to a workspace does not touch the
    /// running app — verified by process id across a start/end pair — so this is
    /// safe to call in the middle of a test.
    static func typeText(_ text: String, udid: String, developerDir: String) throws {
        if case .failure(let reason) = availability(developerDir: developerDir) { throw reason }
        guard let bridge = bridgePath(developerDir: developerDir) else { throw Unavailable.toolMissing }

        // The service must be running for the bridge to reach it; starting an
        // already-running service is a no-op.
        if let server = toolPath(developerDir: developerDir) {
            _ = capture(server, ["start"])
        }

        // Session identifiers are rejected while a previous one with the same
        // name is still settling, so make each call's name unique.
        let session = "sipi-type-\(UInt32.random(in: 0..<UInt32.max))"

        let client = try Client(bridgePath: bridge, developerDir: developerDir)
        // Declared first so it runs LAST: `defer` unwinds in reverse, and the
        // session has to be closed while the bridge is still alive to carry the
        // request. A session left open holds simulator resources.
        defer { client.close() }

        _ = try client.call("DeviceInteractionStartSession", [
            "deviceIdentifier": udid,
            "sessionIdentifier": session,
        ])
        defer {
            _ = try? client.call("DeviceInteractionEndSession",
                                 ["interactionSessionKey": session], timeout: 20)
        }

        // `kbd` takes the rest of the command verbatim, so it must come last and
        // the text needs no escaping — but a newline would end the JSON-RPC line
        // and a control character would not survive, so those go through the
        // documented \u{XXXX} form.
        _ = try client.call("DeviceInteractionSynthesize", [
            // NOTE: this parameter is `interactSessionKey` while EndSession's is
            // `interactionSessionKey`. That inconsistency is Xcode's, not a typo.
            "interactSessionKey": session,
            "interactionCommand": "sender keyboard kbd " + escaped(text),
        ])
    }

    /// Xcode's own escape form for characters that cannot appear literally in
    /// the command string.
    private static func escaped(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            if scalar.value < 0x20 || scalar.value == 0x7F {
                out += String(format: "\\u{%04X}", scalar.value)
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    /// Run a helper and return its standard output, or nil when it cannot be
    /// launched, exits non-zero, or takes longer than `timeout`.
    ///
    /// The timeout is not optional. `mcp-server status` talks to the running
    /// service, and that service stops answering while an approval prompt is on
    /// screen waiting for a human — so an unbounded read here would hang
    /// `sipi doctor` and every text-entry fallback check behind a dialog nobody
    /// may be looking at.
    private static func capture(
        _ path: String,
        _ arguments: [String],
        timeout: TimeInterval = 5
    ) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        // `mcp-server status` puts its warnings on stderr and the state itself on
        // stdout, but it has already moved one across releases; merging them
        // means a relocated line is still seen rather than silently read as
        // "disabled".
        process.standardError = pipe
        guard (try? process.run()) != nil else { return nil }

        // Read on a background thread so a child that neither answers nor exits
        // cannot hold the caller past the timeout, and so the pipe keeps draining
        // (a full pipe would block the child instead of ending it).
        let finished = DispatchSemaphore(value: 0)
        let box = Box()
        Thread {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            box.set(data)
            finished.signal()
        }.start()

        if finished.wait(timeout: .now() + timeout) == .timedOut {
            // Insist: the case this timeout exists for is a helper wedged behind
            // an approval prompt, which may well ignore SIGTERM.
            process.terminate()
            if finished.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 1)
            }
            // Reap it. Without this the killed helper lingers as a zombie and
            // the next status call runs against a duplicate.
            process.waitUntilExit()
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: box.get(), as: UTF8.self)
    }

    /// A value handed between the reading thread and the caller.
    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func set(_ value: Data) {
            lock.lock(); defer { lock.unlock() }
            data = value
        }

        func get() -> Data {
            lock.lock(); defer { lock.unlock() }
            return data
        }
    }

    private static func toolPath(developerDir: String) -> String? {
        let path = developerDir + "/usr/bin/mcp-server"
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    private static func bridgePath(developerDir: String) -> String? {
        let path = developerDir + "/usr/bin/mcpbridge"
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    // MARK: - JSON-RPC over the stdio bridge

    /// One `xcrun mcpbridge` process, spoken to in line-delimited JSON-RPC 2.0.
    ///
    /// Standard output is drained continuously by a background thread rather
    /// than read on demand. Two reasons, both of which have teeth here:
    ///
    /// - A read that blocks cannot be timed out. `availableData` waits for bytes
    ///   or EOF, so a bridge that stays alive and silent — which is exactly what
    ///   happens while an approval prompt is waiting for a human — would hang the
    ///   caller past any deadline, leaving a device-interaction session open on
    ///   the simulator and this process behind.
    /// - A pipe nobody reads fills up. Once it does, the bridge blocks writing to
    ///   it and stops reading its own input, so the next request deadlocks
    ///   against a reply that will never be collected.
    private final class Client {
        private let process = Process()
        private let input = Pipe()
        private let output = Pipe()
        private let lock = NSCondition()
        private var lines: [String] = []
        private var pending = Data()
        /// The bridge's stdout has ended: no further replies will arrive.
        private var streamEnded = false
        /// `close()` has run. Separate from `streamEnded`, because a bridge can
        /// close its output and stay alive — treating that as teardown would
        /// leave the process behind.
        private var torndown = false
        private var nextID = 0

        init(bridgePath: String, developerDir: String) throws {
            process.executableURL = URL(fileURLWithPath: bridgePath)
            var environment = ProcessInfo.processInfo.environment
            environment["DEVELOPER_DIR"] = developerDir
            process.environment = environment
            process.standardInput = input
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                throw Unavailable.failed("could not start mcpbridge: \(error)")
            }
            startDraining()

            // Anything that throws from here on has already spawned the child, so
            // it has to be cleaned up before the error leaves this initializer —
            // a failed handshake must not leak a bridge process.
            do {
                _ = try call("initialize", [
                    "protocolVersion": "2024-11-05",
                    "capabilities": [:] as [String: String],
                    "clientInfo": ["name": "sipi", "version": sipiVersion],
                ], isToolCall: false, timeout: 30)
                notify("notifications/initialized")
            } catch {
                close()
                throw error
            }
        }

        /// Stop the bridge and wait for it to actually go. Idempotent.
        func close() {
            lock.lock()
            if torndown { lock.unlock(); return }
            torndown = true
            lock.broadcast()
            lock.unlock()

            try? input.fileHandleForWriting.close()
            if process.isRunning {
                process.terminate()
                // SIGTERM is a request. Give it a moment, then insist, so a
                // wedged bridge cannot outlive the command that started it.
                if !waitForExit(timeout: 2) {
                    kill(process.processIdentifier, SIGKILL)
                    _ = waitForExit(timeout: 2)
                }
            }
            // The read handle is deliberately NOT closed here: the drain thread
            // may be inside a read on it, and FileHandle is not safe for a
            // concurrent read and close. Terminating the child ends the stream,
            // which ends that thread; the handle goes when this object does.
        }

        private func waitForExit(timeout: TimeInterval) -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning, Date() < deadline {
                usleep(20 * 1000)
            }
            return !process.isRunning
        }

        /// Read stdout forever on its own thread, splitting it into lines. Ends
        /// at EOF or when `close()` runs.
        private func startDraining() {
            let handle = output.fileHandleForReading
            let thread = Thread { [weak self] in
                while true {
                    let chunk = handle.availableData
                    guard let self else { return }
                    if chunk.isEmpty {
                        // EOF: no more replies are coming. Wake anyone waiting so
                        // they fail now instead of at their deadline.
                        self.lock.lock()
                        self.streamEnded = true
                        self.lock.broadcast()
                        self.lock.unlock()
                        return
                    }
                    self.lock.lock()
                    if self.torndown { self.lock.unlock(); return }
                    self.pending.append(chunk)
                    while let index = self.pending.firstIndex(of: 0x0A) {
                        let line = String(decoding: self.pending[self.pending.startIndex..<index], as: UTF8.self)
                        self.pending.removeSubrange(self.pending.startIndex...index)
                        if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                            self.lines.append(line)
                        }
                    }
                    self.lock.broadcast()
                    self.lock.unlock()
                }
            }
            thread.name = "sipi.xcodemcp.reader"
            thread.start()
        }

        @discardableResult
        func call(
            _ name: String,
            _ arguments: [String: Any],
            isToolCall: Bool = true,
            timeout: TimeInterval = 120
        ) throws -> String {
            nextID += 1
            let id = nextID
            let request: [String: Any] = isToolCall
                ? ["jsonrpc": "2.0", "id": id, "method": "tools/call",
                   "params": ["name": name, "arguments": arguments]]
                : ["jsonrpc": "2.0", "id": id, "method": name, "params": arguments]
            try send(request)

            guard let response = awaitResponse(id: id, timeout: timeout) else {
                throw Unavailable.failed(
                    "\(name) did not answer within \(Int(timeout))s. Xcode's service stops answering while an "
                    + "approval prompt is waiting — accept or dismiss it, then try again."
                )
            }
            if let error = response["error"] as? [String: Any] {
                throw Unavailable.failed("\(name): \(error["message"] as? String ?? "\(error)")")
            }
            let result = response["result"] as? [String: Any] ?? [:]
            let text = ((result["content"] as? [[String: Any]]) ?? [])
                .compactMap { $0["text"] as? String }
                .joined()
            if result["isError"] as? Bool == true {
                // Pending is checked FIRST: Xcode's pending message also contains
                // the words that identify the not-approved-yet one, and the two
                // need opposite responses — wait for the prompt already on screen
                // versus raise a new one.
                if text.contains("waiting for the user to approve") {
                    throw Unavailable.approvalPending
                }
                if text.contains("isn't approved") || text.contains("not approved") {
                    throw Unavailable.notApproved(text)
                }
                throw Unavailable.failed("\(name): \(text)")
            }
            return text
        }

        private func notify(_ method: String) {
            try? send(["jsonrpc": "2.0", "method": method, "params": [:] as [String: Any]])
        }

        private func send(_ object: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: object)
            data.append(0x0A)
            do {
                try input.fileHandleForWriting.write(contentsOf: data)
            } catch {
                throw Unavailable.failed("mcpbridge stopped accepting input: \(error)")
            }
        }

        /// Wait for the response carrying `id`. Other traffic (notifications,
        /// replies to calls that already timed out) is discarded.
        private func awaitResponse(id: Int, timeout: TimeInterval) -> [String: Any]? {
            let deadline = Date().addingTimeInterval(timeout)
            lock.lock()
            defer { lock.unlock() }
            while true {
                var index = 0
                while index < lines.count {
                    let line = lines[index]
                    guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                        lines.remove(at: index)
                        continue
                    }
                    if object["id"] as? Int == id {
                        lines.remove(at: index)
                        return object
                    }
                    // Not ours and not a reply we are still waiting for.
                    lines.remove(at: index)
                }
                if streamEnded || torndown { return nil }
                if !lock.wait(until: deadline) { return nil }
            }
        }
    }
}
