// HingeControl.swift
//
// Sets the hinge angle of a foldable simulator (iPhone Duo).
//
// ── Attribution ──────────────────────────────────────────────────────────────
// The mechanism below — the vendor-defined HID usage page/usage, the payload
// dictionary, the IOKit serialization format, and the HID client type that does
// not need an entitlement — is derived from `hinge`
// (https://github.com/artemnovichkov/hinge) by Artem Novichkov, MIT License.
// See THIRD_PARTY_LICENSES.md.
// ─────────────────────────────────────────────────────────────────────────────
//
// Why a guest-side helper rather than something host-side:
//
//   • simctl and devicectl have no verb for it. devicectl's `motion hinge-angle`
//     reads the angle and cannot write it.
//   • sipi's own Indigo HID path cannot carry it. `IndigoHIDMessageForHIDArbitrary`
//     takes four uint32s; the payload is ~150 bytes.
//   • An entitled helper cannot be run at all: backboardd rejects a HID client
//     without `com.apple.private.hid.client.admin`, and CoreSimulator refuses to
//     spawn OR launch any binary that claims that entitlement ("Security policy
//     issue"). Both measured on Xcode 27.1.
//
// What works is a plain, unsigned guest binary using HID client TYPE 4, which
// backboardd accepts without the admin entitlement. That is the whole trick.
//
// The helper is compiled on first use with the iPhoneSimulator SDK the active
// Xcode already ships — no binary is shipped with sipi, and nothing is
// downloaded. The result is cached under ~/.local/share/simpilot/hinge, keyed by
// the source and the SDK it was built against, so a toolchain change rebuilds it
// and an unchanged one costs nothing.

import CryptoKit
import Foundation
import SimCore

public enum HingeError: Error, CustomStringConvertible {
    case noSimulatorSDK(String)
    case compileFailed(String)
    case dispatchFailed(String)

    public var description: String {
        switch self {
        case .noSimulatorSDK(let detail):
            return "cannot locate the iPhoneSimulator SDK to build the hinge helper: \(detail)"
        case .compileFailed(let detail):
            return "failed to build the hinge helper: \(detail)"
        case .dispatchFailed(let detail):
            return "failed to send the hinge angle: \(detail)"
        }
    }
}

public enum HingeControl {

    /// Angles the hardware accepts. 0 is shut, 180 is flat open.
    public static let range: ClosedRange<Double> = 0...180

    /// The largest angle MEASURED to still show the cover, and the smallest
    /// MEASURED to show the inner screen — iPhone Duo / iOS 27.1, stepped in
    /// both directions, same result each way (no hysteresis).
    ///
    /// Two constants rather than one range, because the interesting property is
    /// which angles are KNOWN. 80 and 85 are known; only 81...84 were never
    /// measured. A range invites `<` / `>` comparisons that quietly treat its
    /// own endpoints as unknown, which is exactly the off-by-one that made a
    /// fold to 80° skip waiting for the handover it was about to cause.
    public static let lastCoverDegrees: Double = 80
    public static let firstInnerDegrees: Double = 85

    /// Which screen `degrees` will light, or nil for an angle between the two
    /// measured points, where this build genuinely does not know.
    public static func impliedRole(atAngle degrees: Double) -> DisplayRole? {
        if degrees <= lastCoverDegrees { return .cover }
        if degrees >= firstInnerDegrees { return .inner }
        return nil
    }

    // MARK: - Public API

    /// Set the hinge angle, optionally sweeping to it over `seconds` instead of
    /// jumping in one event.
    ///
    /// A sweep is what Device Hub's slider produces when dragged, and it is worth
    /// having: an app that animates on the fold sees the intermediate angles, and
    /// a single jump can skip whatever it was supposed to react to.
    public static func setAngle(
        udid: String,
        degrees: Double,
        over seconds: Double? = nil
    ) throws {
        let clamped = min(max(degrees, range.lowerBound), range.upperBound)
        let helper = try helperPath()
        var arguments = ["set", format(clamped)]
        if let seconds, seconds > 0 {
            // A sweep needs a starting angle, and only the device knows it. When
            // it cannot be read the jump is the honest fallback: inventing a
            // start would sweep from somewhere the hinge never was.
            if let from = DeviceCtl.hingeAngle(udid: udid) {
                arguments = ["sweep", format(from), format(clamped), format(seconds)]
            }
        }

        let result = try runInGuest(udid: udid, helper: helper, arguments: arguments)
        guard result.succeeded else {
            throw HingeError.dispatchFailed(
                result.stderr.isEmpty ? result.stdout : result.stderr
            )
        }
    }

    /// Whether this toolchain can build the helper at all. Used by `doctor` to
    /// report the capability without attempting a build.
    public static func canBuildHelper() -> Bool {
        (try? simulatorSDKPath()) != nil
    }

    /// The cached helper, building it if this is the first use on this toolchain.
    /// Public so `doctor` can warm it and report a build failure as a capability
    /// note rather than letting the first test step be the one that discovers it.
    @discardableResult
    public static func helperPath() throws -> String {
        let sdk = try simulatorSDKPath()
        let architecture = hostArchitecture()
        let fingerprint = digest(helperSource + "\n" + sdk + "\n" + architecture)
        let directory = cacheDirectory
        let binary = directory.appendingPathComponent("helper-\(fingerprint)")

        if FileManager.default.isExecutableFile(atPath: binary.path) { return binary.path }

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Build somewhere else and move the finished file into place. Compiling
        // straight to `binary.path` publishes a half-written executable under the
        // name everything else treats as "the cached helper", and
        // `isExecutableFile` cannot tell that apart from a good one — so a
        // concurrent sipi, or the next run after this compile is interrupted,
        // hands `simctl spawn` a truncated binary.
        //
        // The scratch name is unique per ATTEMPT, not per process: two builds
        // inside one process would otherwise share a name and clobber each
        // other's intermediate files — and each other's `defer` cleanup. The
        // rename into place is atomic, so whichever attempt finishes last wins
        // with identical content.
        let scratch = "\(binary.lastPathComponent).\(UUID().uuidString)"
        let pendingBinary = directory.appendingPathComponent("\(scratch).building")
        let source = directory.appendingPathComponent("\(scratch).c")
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: pendingBinary)
        }

        do {
            try helperSource.write(to: source, atomically: true, encoding: .utf8)
        } catch {
            throw HingeError.compileFailed("could not write \(source.path): \(error)")
        }

        let compile = try runHost([
            "--sdk", "iphonesimulator", "clang",
            "-arch", architecture,
            "-isysroot", sdk,
            "-mios-simulator-version-min=15.0",
            "-O2",
            "-framework", "CoreFoundation",
            "-framework", "IOKit",
            "-o", pendingBinary.path,
            source.path
        ])
        guard compile.succeeded, FileManager.default.isExecutableFile(atPath: pendingBinary.path) else {
            throw HingeError.compileFailed(
                compile.stderr.isEmpty ? compile.stdout : compile.stderr
            )
        }

        // rename(2) replaces atomically, so a reader sees either the previous
        // file or this one, never a mixture. A process that already has the old
        // path open keeps running from it.
        do {
            _ = try FileManager.default.replaceItemAt(binary, withItemAt: pendingBinary)
        } catch {
            // replaceItemAt fails when there is nothing to replace; that is the
            // ordinary first-build case.
            do {
                try FileManager.default.moveItem(at: pendingBinary, to: binary)
            } catch {
                // Someone else published the same fingerprint between the check
                // and now. Identical content, so theirs will do.
                guard FileManager.default.isExecutableFile(atPath: binary.path) else {
                    throw HingeError.compileFailed("could not install the helper: \(error)")
                }
            }
        }
        return binary.path
    }

    /// Stale helpers, left behind by a toolchain that is no longer active.
    ///
    /// Not pruned automatically. Deleting every other `helper-*` on a cache miss
    /// is a one-line optimisation that can delete the binary a CONCURRENT sipi
    /// resolved a moment ago and is about to spawn — and each file is ~35 KB, so
    /// the whole history of a machine's Xcode betas costs less than one
    /// screenshot. `sipi uninstall` removes the directory outright.
    public static var cacheDirectory: URL {
        dataDirectory.appendingPathComponent("hinge", isDirectory: true)
    }

    // MARK: - Plumbing

    /// `~/.local/share/simpilot` — the same data directory the installer uses.
    private static var dataDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".local/share/simpilot", isDirectory: true)
    }

    /// The simulator runs the host's architecture, so the helper must be built
    /// for it — arm64 on Apple silicon, x86_64 on Intel.
    private static func hostArchitecture() -> String {
        #if arch(x86_64)
        return "x86_64"
        #else
        return "arm64"
        #endif
    }

    private static func simulatorSDKPath() throws -> String {
        let result = try runHost(["--sdk", "iphonesimulator", "--show-sdk-path"])
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.succeeded, !path.isEmpty,
              FileManager.default.fileExists(atPath: path)
        else {
            throw HingeError.noSimulatorSDK(
                result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return path
    }

    private static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8))
            .prefix(8)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Angles and durations reach a C `atof`, so they must be written the way C
    /// reads them regardless of the host locale — a comma decimal separator would
    /// truncate 22,5 to 22.
    static func format(_ value: Double) -> String {
        String(format: "%g", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func runHost(_ arguments: [String]) throws -> SimShellResult {
        try spawn(executable: "/usr/bin/xcrun", arguments: arguments)
    }

    private static func runInGuest(
        udid: String,
        helper: String,
        arguments: [String]
    ) throws -> SimShellResult {
        try spawn(
            executable: "/usr/bin/xcrun",
            arguments: ["simctl", "spawn", udid, helper] + arguments
        )
    }

    private static func spawn(executable: String, arguments: [String]) throws -> SimShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        do {
            try process.run()
        } catch {
            throw HingeError.dispatchFailed(error.localizedDescription)
        }
        let out = outPipe.fileHandleForReading.readDataToEndOfFile()
        let err = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return SimShellResult(
            stdout: String(decoding: out, as: UTF8.self),
            stderr: String(decoding: err, as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }
}
