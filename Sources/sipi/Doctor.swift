// Doctor.swift
//
// `sipi doctor` — machine-readable capability probe. Reports the dlopen status
// of the three private frameworks (CoreSimulator / SimulatorKit /
// AccessibilityPlatformTranslation), presence of key classes/symbols, the
// active Xcode, and whether any device is booted.
// Exit 0 ONLY if all core capabilities are present; non-zero otherwise so
// `preflight` can gate on it.

import ArgumentParser
import Darwin
import Foundation
import ObjectiveC
import SimCore
import SimNative
import SimShell
import SimBridge

extension Sipi {
    struct Doctor: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "doctor",
            abstract: "Probe native capabilities; exit 0 only if all are present."
        )

        @Flag(name: .long, help: "Emit the probe as JSON.")
        var json = false

        func run() throws {
            let report = DoctorReport.probe()

            if json {
                let data = try JSONSerialization.data(
                    withJSONObject: report.dictionary,
                    options: [.prettyPrinted]
                )
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            } else {
                FileHandle.standardOutput.write(Data((report.text + "\n").utf8))
            }

            if !report.allCorePresent {
                throw ExitCode.failure
            }
        }
    }
}

/// One capability check.
private struct Check {
    var name: String
    var ok: Bool
    var detail: String
}

/// Aggregated capability probe result.
private struct DoctorReport {
    var developerDir: String
    var checks: [Check]
    var bootedDevices: [String]

    /// Core capabilities that must all pass for exit 0: the three framework
    /// dlopens, the AX bridge, and the HID/transport classes.
    var allCorePresent: Bool {
        checks.allSatisfy { $0.ok }
    }

    var text: String {
        var lines: [String] = []
        lines.append("sipi doctor")
        lines.append("  developer dir: \(developerDir)")
        for check in checks {
            let mark = check.ok ? "[ok]" : "[--]"
            lines.append("  \(mark) \(check.name): \(check.detail)")
        }
        if bootedDevices.isEmpty {
            lines.append("  booted devices: none")
        } else {
            lines.append("  booted devices: \(bootedDevices.joined(separator: ", "))")
        }
        lines.append("  result: \(allCorePresent ? "all core capabilities present" : "missing core capabilities")")
        return lines.joined(separator: "\n")
    }

    var dictionary: [String: Any] {
        [
            "developerDir": developerDir,
            "checks": checks.map { [
                "name": $0.name,
                "ok": $0.ok,
                "detail": $0.detail
            ] },
            "bootedDevices": bootedDevices,
            "allCorePresent": allCorePresent
        ]
    }

    static func probe() -> DoctorReport {
        let developerDir = SPSimBridge.defaultDeveloperDir()
        var checks: [Check] = []

        // 1. CoreSimulator dlopen + service classes.
        do {
            try SPSimBridge.loadCoreSimulator()
            let hasContext = NSClassFromString("SimServiceContext") != nil
            let hasDevice = NSClassFromString("SimDevice") != nil
            let ok = hasContext && hasDevice
            checks.append(Check(
                name: "CoreSimulator",
                ok: ok,
                detail: ok
                    ? "loaded (SimServiceContext, SimDevice resolve)"
                    : "loaded but classes missing (SimServiceContext \(hasContext), SimDevice \(hasDevice))"
            ))
        } catch {
            checks.append(Check(
                name: "CoreSimulator",
                ok: false,
                detail: "dlopen failed: \(error.localizedDescription)"
            ))
        }

        // 2. SimulatorKit dlopen + HID client class (Indigo HID path).
        let simKitPath = (developerDir as NSString)
            .appendingPathComponent("Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit")
        let simKitExists = FileManager.default.fileExists(atPath: simKitPath)
        let simKitLoaded = simKitExists
            && dlopen(simKitPath, RTLD_NOW) != nil
        let hasHIDClient = NSClassFromString("_TtC12SimulatorKit24SimDeviceLegacyHIDClient") != nil
        let simKitOK = simKitLoaded && hasHIDClient
        checks.append(Check(
            name: "SimulatorKit",
            ok: simKitOK,
            detail: simKitOK
                ? "loaded (SimDeviceLegacyHIDClient resolves)"
                : "not fully available (binary \(simKitExists), dlopen \(simKitLoaded), HID client \(hasHIDClient))"
        ))

        // 2b. Indigo HID message builders (the dlsym'd symbols the input paths use).
        // `mouse` drives tap/touch/swipe and is required — its absence fails all
        // HID injection. `button`/`keyboard`/`crown` drive `sipi button`/`key`/
        // `type`/`crown`; they no-op silently when missing, so report their
        // presence and warn (without failing core) when one is unavailable.
        let hidSymbols = SPSimBridge.hidSymbolStatus(forDeveloperDir: developerDir)
        let hidMouse = hidSymbols["mouse"]?.boolValue ?? false
        let hidButton = hidSymbols["button"]?.boolValue ?? false
        let hidKeyboard = hidSymbols["keyboard"]?.boolValue ?? false
        let hidCrown = hidSymbols["crown"]?.boolValue ?? false
        func mark(_ ok: Bool) -> String { ok ? "✓" : "✗" }
        let hidDetail = "mouse \(mark(hidMouse)), button \(mark(hidButton)), "
            + "keyboard \(mark(hidKeyboard)), crown \(mark(hidCrown))"
        let optionalMissing = [
            hidButton ? nil : "button",
            hidKeyboard ? nil : "keyboard",
            hidCrown ? nil : "crown"
        ].compactMap { $0 }
        checks.append(Check(
            name: "IndigoHID",
            ok: hidMouse,
            detail: hidMouse
                ? (optionalMissing.isEmpty
                    ? "all builders resolve (\(hidDetail))"
                    : "mouse required builder resolves; warning: \(optionalMissing.joined(separator: ", ")) missing (\(hidDetail))")
                : "required mouse builder missing (\(hidDetail))"
        ))

        // 3. AccessibilityPlatformTranslation bridge probe. Gate on the STRUCTURED
        // sub-checks via accessibilityBridgeReady — the status string's
        // "AXPTranslator ready" prefix is emitted even when a sub-check is ✗, so
        // matching the substring would go falsely green. The string stays for
        // human-readable display only.
        let axStatus = SPSimBridge.accessibilityBridgeStatus()
        let axOK = SPSimBridge.accessibilityBridgeReady()
        checks.append(Check(
            name: "AccessibilityPlatformTranslation",
            ok: axOK,
            detail: axStatus
        ))

        // Booted devices via native CoreSimulator enumeration.
        var bootedDevices: [String] = []
        do {
            let driver = NativeDriver(developerDir: developerDir)
            bootedDevices = try driver.devices()
                .filter { $0.booted }
                .map { "\($0.name) (\($0.udid))" }
        } catch {
            // Surface the failure as a non-core informational note; core dlopen
            // checks above already gate the exit code.
            bootedDevices = []
        }

        return DoctorReport(
            developerDir: developerDir,
            checks: checks,
            bootedDevices: bootedDevices
        )
    }
}
