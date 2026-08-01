// DeviceState.swift
//
// Device-state commands that ride on `xcrun devicectl`, which Xcode 27 taught to
// speak to simulators. These cover facets simctl never exposed:
//
//   biometrics  Face ID / Touch ID enrollment and match/no-match events, so a
//               biometric login path can be tested end to end instead of being
//               skipped.
//   appearance  The full accessibility appearance surface — reduce motion,
//               reduce transparency, show borders, color filters, Liquid Glass
//               opacity, Larger Accessibility Sizes — read and write. simctl
//               only ever offered light/dark, content size, and increase
//               contrast.
//   voiceover   VoiceOver on/off, the state an accessibility pass runs under.
//
// All three degrade with a clear message on a toolchain whose devicectl cannot
// target simulators (Xcode 26 and earlier), rather than surfacing a raw
// device-not-found error.

import ArgumentParser
import Foundation
import SimShell

/// Shared precondition: devicectl must be able to target simulators. Xcode 27
/// loads a `SimulatorCoreDevicePlugin`; earlier toolchains list physical devices
/// only.
private func requireDeviceCtl(_ feature: String) throws {
    guard DeviceCtl.isSimulatorCapable() else {
        throw ValidationError(
            """
            \(feature) needs a devicectl that can target simulators, which arrived in Xcode 27. \
            This toolchain's devicectl lists no SimulatorCoreDevicePlugin \
            (check `xcrun devicectl list plugins`). Select Xcode 27 or later with xcode-select.
            """
        )
    }
}

private func emitJSON(_ object: [String: Any]) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

// MARK: - biometrics

extension Sipi {
    struct Biometrics: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "biometrics",
            abstract: "Control Face ID / Touch ID enrollment and deliver match or no-match events.",
            discussion: """
            Operations:
              status     Report the enrollment state of each supported biometric type.
              enroll     Enroll every supported biometric type.
              unenroll   Unenroll every supported biometric type.
              match      Deliver a successful biometric match to the active prompt.
              no-match   Deliver a failed biometric match to the active prompt.

            match / no-match only reach the app while enrollment is on — an unenrolled
            device shows the passcode fallback instead of the biometric prompt, so the
            event has nothing to answer. Enroll first, then present the prompt, then
            send the match.
            """
        )

        @Argument(help: "Simulator UDID.")
        var udid: String

        @Argument(help: "Operation: status, enroll, unenroll, match, no-match.")
        var operation: String

        @Flag(name: .long, help: "Emit the result as JSON.")
        var json = false

        static let operations: Set<String> = ["status", "enroll", "unenroll", "match", "no-match"]

        func validate() throws {
            guard Self.operations.contains(operation) else {
                throw ValidationError(
                    "Unknown biometrics operation '\(operation)'. Valid: "
                    + Self.operations.sorted().joined(separator: ", ") + ".")
            }
        }

        func run() throws {
            try requireDeviceCtl("sipi biometrics")
            do {
                switch operation {
                case "status":
                    let state = try DeviceCtl.biometricsEnrollment(udid: udid)
                    if json {
                        try emitJSON(["biometrics": state])
                    } else if state.isEmpty {
                        print("no biometric hardware")
                    } else {
                        for (type, enabled) in state.sorted(by: { $0.key < $1.key }) {
                            print("\(type): \(enabled ? "enrolled" : "not enrolled")")
                        }
                    }
                case "enroll":
                    try DeviceCtl.setBiometricsEnrollment(udid: udid, enabled: true)
                    print("ok")
                case "unenroll":
                    try DeviceCtl.setBiometricsEnrollment(udid: udid, enabled: false)
                    print("ok")
                case "match":
                    try DeviceCtl.simulateBiometrics(udid: udid, success: true)
                    print("ok")
                case "no-match":
                    try DeviceCtl.simulateBiometrics(udid: udid, success: false)
                    print("ok")
                default:
                    throw ValidationError("Unknown biometrics operation '\(operation)'.")
                }
            } catch let error as DeviceCtlError {
                throw ValidationError("biometrics \(operation) failed: \(error)")
            }
        }
    }
}

// MARK: - appearance

extension Sipi {
    struct Appearance: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "appearance",
            abstract: "Read or set the full appearance / accessibility state (reduce motion, color filters, Liquid Glass, and more).",
            discussion: """
            With no set options this READS the current state; pass any option to WRITE.
            All writes go out in a single devicectl call.

            Reading returns every facet the runtime reports, so a harness can capture a
            baseline and restore it afterward. A facet the runtime does not support is
            omitted from the JSON rather than reported as off.

            simctl covers only light/dark, content size, and increase contrast; the
            remaining facets here have no simctl equivalent.
            """
        )

        @Argument(help: "Simulator UDID.")
        var udid: String

        @Flag(name: .long, help: "Emit the state as JSON (read mode only).")
        var json = false

        @Option(name: .long, help: "User interface style: light or dark.")
        var mode: String?

        @Option(name: .customLong("look-and-feel"), help: "Look and feel: clear or tinted.")
        var lookAndFeel: String?

        @Option(name: .customLong("text-size"), help: "Text size category (e.g. large, accessibility-extra-large).")
        var textSize: String?

        @Option(name: .customLong("increase-contrast"), help: "Increase Contrast: on or off.")
        var increaseContrast: String?

        @Option(name: .customLong("reduce-motion"), help: "Reduce Motion: on or off.")
        var reduceMotion: String?

        @Option(name: .customLong("reduce-transparency"), help: "Reduce Transparency: on or off.")
        var reduceTransparency: String?

        @Option(name: .customLong("show-borders"), help: "Button Shapes / show borders: on or off.")
        var showBorders: String?

        @Option(name: .customLong("liquid-glass-opacity"), help: "Liquid Glass opacity, 0.0 (translucent) to 1.0 (opaque).")
        var liquidGlassOpacity: Double?

        @Option(name: .customLong("color-filter"), help: "Color filter: on or off.")
        var colorFilter: String?

        @Option(
            name: .customLong("color-filter-type"),
            help: "Color filter type: grayscale, protanopia, deuteranopia, tritanopia."
        )
        var colorFilterType: String?

        @Option(name: .customLong("color-filter-intensity"), help: "Color filter intensity, 0.25 to 1.0 (not used by grayscale).")
        var colorFilterIntensity: Double?

        @Option(
            name: .customLong("larger-accessibility-sizes"),
            help: "Larger Accessibility Sizes: on or off (required before the accessibility text sizes apply)."
        )
        var largerAccessibilitySizes: String?

        private static let onOff: Set<String> = ["on", "off"]
        private static let modes: Set<String> = ["light", "dark"]
        private static let looks: Set<String> = ["clear", "tinted"]
        private static let filterTypes: Set<String> = ["grayscale", "protanopia", "deuteranopia", "tritanopia"]

        func validate() throws {
            func checkEnum(_ value: String?, _ allowed: Set<String>, _ flag: String) throws {
                guard let value else { return }
                guard allowed.contains(value) else {
                    throw ValidationError("\(flag) must be one of: " + allowed.sorted().joined(separator: ", ") + ".")
                }
            }
            try checkEnum(mode, Self.modes, "--mode")
            try checkEnum(lookAndFeel, Self.looks, "--look-and-feel")
            try checkEnum(colorFilterType, Self.filterTypes, "--color-filter-type")
            for (value, flag) in [
                (increaseContrast, "--increase-contrast"),
                (reduceMotion, "--reduce-motion"),
                (reduceTransparency, "--reduce-transparency"),
                (showBorders, "--show-borders"),
                (colorFilter, "--color-filter"),
                (largerAccessibilitySizes, "--larger-accessibility-sizes")
            ] {
                try checkEnum(value, Self.onOff, flag)
            }
            if let liquidGlassOpacity, !(0.0...1.0).contains(liquidGlassOpacity) {
                throw ValidationError("--liquid-glass-opacity must be between 0.0 and 1.0.")
            }
            if let colorFilterIntensity, !(0.25...1.0).contains(colorFilterIntensity) {
                throw ValidationError("--color-filter-intensity must be between 0.25 and 1.0.")
            }
            // devicectl rejects the pair outright; catching it here keeps the
            // error short instead of surfacing devicectl's usage dump.
            if colorFilterType == "grayscale", colorFilterIntensity != nil {
                throw ValidationError("--color-filter-intensity does not apply to the grayscale filter; drop one of them.")
            }
            if json && !settings.isEmpty {
                throw ValidationError("--json applies to reading only; drop it when setting appearance facets.")
            }
        }

        /// The requested writes, in a stable order.
        private var settings: [AppearanceSetting] {
            func boolean(_ value: String?) -> Bool? {
                guard let value else { return nil }
                return value == "on"
            }
            var settings: [AppearanceSetting] = []
            if let mode { settings.append(.mode(mode)) }
            if let lookAndFeel { settings.append(.lookAndFeel(lookAndFeel)) }
            if let textSize { settings.append(.textSize(textSize)) }
            if let value = boolean(increaseContrast) { settings.append(.increaseContrast(value)) }
            if let value = boolean(reduceMotion) { settings.append(.reduceMotion(value)) }
            if let value = boolean(reduceTransparency) { settings.append(.reduceTransparency(value)) }
            if let value = boolean(showBorders) { settings.append(.showBorders(value)) }
            if let liquidGlassOpacity { settings.append(.liquidGlassOpacity(liquidGlassOpacity)) }
            if let value = boolean(colorFilter) { settings.append(.colorFilter(value)) }
            if let colorFilterType { settings.append(.colorFilterType(colorFilterType)) }
            if let colorFilterIntensity { settings.append(.colorFilterIntensity(colorFilterIntensity)) }
            if let value = boolean(largerAccessibilitySizes) { settings.append(.largerAccessibilitySizes(value)) }
            return settings
        }

        func run() throws {
            try requireDeviceCtl("sipi appearance")
            let writes = settings
            do {
                if !writes.isEmpty {
                    // devicectl exits 0 for `--look-and-feel` even on a runtime
                    // that offers a single look (iOS 27 has only "Liquid Glass"),
                    // so the write silently does nothing. Check before writing
                    // rather than printing ok over a no-op.
                    if lookAndFeel != nil {
                        let state = try DeviceCtl.appearanceState(udid: udid)
                        guard state.supportsLookAndFeelSwitching else {
                            throw ValidationError(
                                """
                                --look-and-feel cannot be set on this runtime: it offers only \
                                \(state.supportedLooksAndFeels.joined(separator: ", ")). devicectl accepts \
                                the flag and ignores it.
                                """
                            )
                        }
                    }
                    try DeviceCtl.setAppearance(udid: udid, settings: writes)
                    print("ok")
                    return
                }
                let state = try DeviceCtl.appearanceState(udid: udid)
                if json {
                    try emitJSON(state.jsonObject)
                } else {
                    for (key, value) in state.jsonObject.sorted(by: { $0.key < $1.key }) {
                        print("\(key): \(value)")
                    }
                }
            } catch let error as DeviceCtlError {
                throw ValidationError("appearance failed: \(error)")
            }
        }
    }
}

// MARK: - voiceover

extension Sipi {
    struct VoiceOver: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "voiceover",
            abstract: "Read or set VoiceOver on the simulator.",
            discussion: """
            With no flag this reports the current state. VoiceOver changes how the
            accessibility tree is presented and how gestures are interpreted, so turn it
            on for an accessibility pass and back off afterward.

            Driving VoiceOver navigation itself (move forward / read the spoken string)
            needs XCUITest's XCUIVoiceOverService from inside a UI test target; this
            command controls the state, not the cursor.
            """
        )

        @Argument(help: "Simulator UDID.")
        var udid: String

        @Flag(name: .long, help: "Turn VoiceOver on.")
        var enable = false

        @Flag(name: .long, help: "Turn VoiceOver off.")
        var disable = false

        @Flag(name: .long, help: "Emit the state as JSON (read mode only).")
        var json = false

        func validate() throws {
            if enable && disable {
                throw ValidationError("Pass only one of --enable or --disable.")
            }
            if json && (enable || disable) {
                throw ValidationError("--json applies to reading only.")
            }
        }

        func run() throws {
            try requireDeviceCtl("sipi voiceover")
            do {
                if enable || disable {
                    try DeviceCtl.setVoiceOver(udid: udid, enabled: enable)
                    print("ok")
                    return
                }
                let enabled = try DeviceCtl.voiceOver(udid: udid)
                if json {
                    try emitJSON(["enabled": enabled ?? NSNull()])
                } else {
                    print(enabled.map { $0 ? "enabled" : "disabled" } ?? "unknown")
                }
            } catch let error as DeviceCtlError {
                throw ValidationError("voiceover failed: \(error)")
            }
        }
    }
}
