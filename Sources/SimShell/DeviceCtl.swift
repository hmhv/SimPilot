// DeviceCtl.swift
//
// Typed Process() wrappers over the public `xcrun devicectl`. Xcode 27 made the
// simulator a first-class CoreDevice target (`SimulatorCoreDevicePlugin`), which
// unlocks device facets simctl never exposed: face-up / face-down orientation,
// biometric enrollment and match events, VoiceOver, and the full accessibility
// appearance surface (reduce motion / reduce transparency / show borders /
// color filter / Liquid Glass opacity).
//
// Everything here is public tooling — no private frameworks, no SimBridge. Each
// call shells out to `xcrun devicectl` and, where a value is read back, parses
// the stable `--json-output -` document rather than the human-readable text.
//
// Availability: devicectl only speaks to simulators from Xcode 27 on. Callers
// that need a graceful degradation path check `isSimulatorCapable()` first
// instead of treating a missing subcommand as a hard failure.

import Foundation

public enum DeviceCtlError: Error, CustomStringConvertible {
    case launchFailed(String)
    case nonZeroExit(command: String, code: Int32, stderr: String)
    case unparsableOutput(command: String)

    public var description: String {
        switch self {
        case .launchFailed(let message):
            return "failed to launch devicectl: \(message)"
        case .nonZeroExit(let command, let code, let stderr):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "`\(command)` exited \(code)\(trimmed.isEmpty ? "" : ": \(trimmed)")"
        case .unparsableOutput(let command):
            return "`\(command)` returned output this build cannot parse"
        }
    }
}

/// The accessibility/appearance facets `devicectl device info appearance`
/// reports and `devicectl device settings appearance` can set. Every field is
/// optional because the set is runtime-dependent — an older runtime simply omits
/// the keys it does not support, and a nil field means "unknown / unsupported",
/// never "off".
public struct AppearanceState: Equatable, Sendable {
    public var userInterfaceStyle: String?
    public var lookAndFeel: String?
    /// The look-and-feel display names this runtime offers. iOS 26 reports
    /// `["Clear Liquid Glass", "Tinted Liquid Glass"]`; iOS 27 reports only
    /// `["Liquid Glass"]`, meaning `--look-and-feel` has nothing to switch
    /// between and devicectl accepts the write while ignoring it.
    public var supportedLooksAndFeels: [String]
    public var textSize: String?
    public var increaseContrast: Bool?
    public var reduceMotion: Bool?
    public var reduceTransparency: Bool?
    public var showBorders: Bool?
    public var liquidGlassOpacity: Double?
    public var colorFilterEnabled: Bool?
    public var colorFilterType: String?
    public var colorFilterIntensity: Double?
    public var largerAccessibilitySizes: Bool?

    public init(
        userInterfaceStyle: String? = nil,
        lookAndFeel: String? = nil,
        supportedLooksAndFeels: [String] = [],
        textSize: String? = nil,
        increaseContrast: Bool? = nil,
        reduceMotion: Bool? = nil,
        reduceTransparency: Bool? = nil,
        showBorders: Bool? = nil,
        liquidGlassOpacity: Double? = nil,
        colorFilterEnabled: Bool? = nil,
        colorFilterType: String? = nil,
        colorFilterIntensity: Double? = nil,
        largerAccessibilitySizes: Bool? = nil
    ) {
        self.userInterfaceStyle = userInterfaceStyle
        self.lookAndFeel = lookAndFeel
        self.supportedLooksAndFeels = supportedLooksAndFeels
        self.textSize = textSize
        self.increaseContrast = increaseContrast
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
        self.showBorders = showBorders
        self.liquidGlassOpacity = liquidGlassOpacity
        self.colorFilterEnabled = colorFilterEnabled
        self.colorFilterType = colorFilterType
        self.colorFilterIntensity = colorFilterIntensity
        self.largerAccessibilitySizes = largerAccessibilitySizes
    }

    /// Whether any facet is set. An all-nil state means the probe found nothing
    /// usable, which callers treat as "cannot restore" rather than "restore to
    /// defaults".
    public var isEmpty: Bool { self == AppearanceState() }

    /// The captured look and feel as the token `settings appearance` accepts, or
    /// nil when it cannot be written back.
    ///
    /// devicectl reports a display name ("Clear Liquid Glass") but accepts a
    /// short token ("clear"). A runtime whose only look is plain "Liquid Glass"
    /// (iOS 27) has no token to restore to, so this yields nil rather than
    /// guessing — writing the wrong token would change state the test never
    /// touched.
    public var restorableLookAndFeel: String? {
        guard let lookAndFeel else { return nil }
        let lowered = lookAndFeel.lowercased()
        if lowered.hasPrefix("clear") { return "clear" }
        if lowered.hasPrefix("tinted") { return "tinted" }
        return nil
    }

    /// Whether this runtime can actually switch look and feel. When it cannot,
    /// devicectl still exits 0 for `--look-and-feel`, so callers must check this
    /// to avoid reporting a change that never happened.
    public var supportsLookAndFeelSwitching: Bool { supportedLooksAndFeels.count > 1 }

    /// Why this state's colour filter could not be put back after a run that
    /// changes the facets named by the flags — or nil when it can.
    ///
    /// Restorability is a property of the baseline AND of what the run touches,
    /// not of the baseline alone. A facet the run never writes is still sitting
    /// on the device afterward, so it needs nothing from the restore: a run that
    /// only toggles the filter off and on leaves an out-of-range stored intensity
    /// exactly as it found it, and refusing that run would block a safe
    /// operation.
    ///
    /// For a facet the run DOES change, the restore has to write the baseline
    /// value back, so the baseline must both HAVE that value and be able to take
    /// it back:
    ///
    /// - `colorFilterType` needs a reported value; without one the run's kind
    ///   stays.
    /// - `colorFilterIntensity` needs a reported value inside 0.25...1.0, the
    ///   range devicectl accepts.
    ///
    /// With the filter OFF in the baseline none of this applies: the restore
    /// switches it off and the screen matches, whatever is configured behind it.
    ///
    /// A `grayscale` baseline blocks an intensity change, because devicectl
    /// refuses an intensity alongside grayscale and the restore is a single
    /// batch. A staged restore (write the intensity under a temporary
    /// non-grayscale kind, then set grayscale) might lift that, but the ordering
    /// is unverified against a real runtime, so this refuses rather than guesses.
    public func colorFilterRestoreBlocker(
        changingType: Bool,
        changingIntensity: Bool
    ) -> String? {
        guard colorFilterEnabled == true else { return nil }
        if changingType, colorFilterType == nil {
            return "this runtime does not report the current colour-filter type, so the run's kind "
                + "would stay on the device and the screen would not go back to how it looked"
        }
        if changingIntensity {
            // Grayscale first, and deliberately: it decides the CONSEQUENCE, and
            // the checks below would otherwise answer for it with the wrong one.
            // Here the kind is restorable and grayscale ignores intensity, so the
            // screen does come back — only the stored value leaks. Saying "the
            // screen would keep the run's intensity" would be false.
            if colorFilterType == "grayscale" {
                return "the colour filter is set to grayscale and devicectl refuses an intensity "
                    + "alongside it, so the original intensity could not be written back. The screen "
                    + "would return to grayscale, but the run's intensity would persist in the "
                    + "device's stored settings"
            }
            guard let colorFilterIntensity else {
                return "this runtime does not report the current colour-filter intensity, so the "
                    + "run's intensity would stay and the screen would not go back to how it looked"
            }
            guard (0.25...1.0).contains(colorFilterIntensity) else {
                return "the current colour-filter intensity (\(colorFilterIntensity)) is outside the "
                    + "0.25...1.0 range devicectl accepts, so it could not be written back and the "
                    + "filter would return at the run's intensity instead"
            }
        }
        return nil
    }

    /// A stable dictionary for JSON emission and result diffing. Nil fields are
    /// omitted so consumers can tell "unsupported" from "false".
    public var jsonObject: [String: Any] {
        var object: [String: Any] = [:]
        if let userInterfaceStyle { object["user-interface-style"] = userInterfaceStyle }
        if let lookAndFeel { object["look-and-feel"] = lookAndFeel }
        if let textSize { object["text-size"] = textSize }
        if let increaseContrast { object["increase-contrast"] = increaseContrast }
        if let reduceMotion { object["reduce-motion"] = reduceMotion }
        if let reduceTransparency { object["reduce-transparency"] = reduceTransparency }
        if let showBorders { object["show-borders"] = showBorders }
        if let liquidGlassOpacity { object["liquid-glass-opacity"] = liquidGlassOpacity }
        if let colorFilterEnabled { object["color-filter"] = colorFilterEnabled }
        if let colorFilterType { object["color-filter-type"] = colorFilterType }
        if let colorFilterIntensity { object["color-filter-intensity"] = colorFilterIntensity }
        if let largerAccessibilitySizes { object["larger-accessibility-sizes"] = largerAccessibilitySizes }
        return object
    }
}

/// One appearance facet to write. Modeled as an enum rather than a partially
/// filled `AppearanceState` so a caller cannot accidentally write back "nil
/// means leave alone" as "nil means off".
public enum AppearanceSetting: Equatable, Sendable {
    case mode(String)                    // light | dark
    case lookAndFeel(String)             // clear | tinted
    case textSize(String)
    case increaseContrast(Bool)
    case reduceMotion(Bool)
    case reduceTransparency(Bool)
    case showBorders(Bool)
    case liquidGlassOpacity(Double)
    case colorFilter(Bool)
    case colorFilterType(String)
    case colorFilterIntensity(Double)
    case largerAccessibilitySizes(Bool)

    /// The `devicectl device settings appearance` flag pair for this facet.
    public var arguments: [String] {
        func onOff(_ value: Bool) -> String { value ? "on" : "off" }
        switch self {
        case .mode(let value): return ["--mode", value]
        case .lookAndFeel(let value): return ["--look-and-feel", value]
        case .textSize(let value): return ["--text-size", value]
        case .increaseContrast(let value): return ["--increase-contrast", onOff(value)]
        case .reduceMotion(let value): return ["--reduce-motion", onOff(value)]
        case .reduceTransparency(let value): return ["--reduce-transparency", onOff(value)]
        case .showBorders(let value): return ["--show-borders", onOff(value)]
        case .liquidGlassOpacity(let value): return ["--liquid-glass-opacity", Self.decimal(value)]
        case .colorFilter(let value): return ["--color-filter", onOff(value)]
        case .colorFilterType(let value): return ["--color-filter-type", value]
        case .colorFilterIntensity(let value): return ["--color-filter-intensity", Self.decimal(value)]
        case .largerAccessibilitySizes(let value): return ["--larger-accessibility-sizes", onOff(value)]
        }
    }

    /// Locale-independent decimal rendering — devicectl parses `0.5`, never `0,5`.
    private static func decimal(_ value: Double) -> String {
        String(format: "%g", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

public enum DeviceCtl {
    /// Orientation names `devicectl device orientation set` accepts. Unlike the
    /// native PurpleEvent SET (UIDeviceOrientation 1...4) this covers face-up and
    /// face-down, and unlike the osascript menu path it needs no GUI app.
    public static let orientationNames = [
        "portrait", "portraitUpsideDown", "landscapeLeft", "landscapeRight", "faceUp", "faceDown"
    ]

    // MARK: - Process plumbing

    private static func run(_ args: [String], timeout: TimeInterval? = nil) throws -> SimShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        var arguments = ["devicectl"] + args
        if let timeout {
            arguments += ["--timeout", String(format: "%g", locale: Locale(identifier: "en_US_POSIX"), timeout)]
        }
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            throw DeviceCtlError.launchFailed(error.localizedDescription)
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

    @discardableResult
    private static func runChecked(_ args: [String], timeout: TimeInterval? = nil) throws -> String {
        let result = try run(args, timeout: timeout)
        guard result.succeeded else {
            throw DeviceCtlError.nonZeroExit(
                command: "xcrun devicectl " + args.joined(separator: " "),
                code: result.exitCode,
                stderr: result.stderr.isEmpty ? result.stdout : result.stderr
            )
        }
        return result.stdout
    }

    /// Run a read command with `--json-output -` and return the `result` object.
    /// devicectl routes its human-readable progress to stderr in this mode, so
    /// stdout is a single JSON document.
    private static func runJSON(_ args: [String], timeout: TimeInterval? = nil) throws -> [String: Any] {
        let stdout = try runChecked(args + ["--json-output", "-"], timeout: timeout)
        guard let data = stdout.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw DeviceCtlError.unparsableOutput(command: "xcrun devicectl " + args.joined(separator: " "))
        }
        return (root["result"] as? [String: Any]) ?? root
    }

    // MARK: - Availability

    /// Whether this toolchain's devicectl can drive simulators. Xcode 27 loads a
    /// `SimulatorCoreDevicePlugin`; earlier toolchains list physical devices only,
    /// so every simulator-targeting call would fail with a device-not-found error.
    ///
    /// Only a DEFINITIVE answer is cached — one where devicectl ran and reported
    /// its plugin list. A launch failure, a timeout, or a non-zero exit says
    /// nothing about the toolchain (a loaded machine, a coredevice daemon still
    /// starting), and caching it would disable the whole device-state surface for
    /// the life of the process over one bad moment. Those retry on the next call;
    /// the answer that cannot change is the only one worth keeping.
    public static func isSimulatorCapable() -> Bool {
        if let cached = simulatorCapableCache { return cached }
        guard let result = try? run(["list", "plugins"], timeout: 20), result.succeeded else {
            return false
        }
        let capable = result.stdout.contains("SimulatorCoreDevicePlugin")
        simulatorCapableCache = capable
        return capable
    }

    private nonisolated(unsafe) static var simulatorCapableCache: Bool?

    // MARK: - Orientation

    /// Set the device orientation through devicectl. `name` must be one of
    /// `orientationNames`. This is the headless, locale-independent path for
    /// face-up / face-down, which the native PurpleEvent SET cannot express and
    /// which previously required clicking Simulator.app's menu — an app Xcode 27
    /// removed entirely.
    public static func setOrientation(udid: String, name: String) throws {
        try runChecked(["device", "orientation", "set", "--device", udid, name], timeout: 30)
    }

    /// The physical orientation devicectl reports, including the flat states the
    /// SimulatorKit READ cannot express.
    ///
    /// devicectl answers with two keys: `deviceOrientation` is the true physical
    /// orientation and reads `faceUp` / `faceDown` / `unknown`, while
    /// `deviceOrientationNonFlat` always holds one of the four upright
    /// orientations. `flat` is non-nil only when the device is actually face-up or
    /// face-down, so callers can report the flat state without losing the upright
    /// one underneath it.
    public struct PhysicalOrientation: Equatable, Sendable {
        public var deviceOrientation: String
        public var nonFlat: String?
        public var isLocked: Bool?

        /// `face-up` / `face-down` in SimPilot's hyphenated naming, or nil when the
        /// device is upright.
        public var flat: String? {
            switch deviceOrientation {
            case "faceUp": return "face-up"
            case "faceDown": return "face-down"
            default: return nil
            }
        }
    }

    /// Read the physical orientation, or nil when devicectl reports nothing this
    /// build can parse.
    public static func orientation(udid: String) throws -> PhysicalOrientation? {
        let result = try runJSON(["device", "orientation", "get", "--device", udid], timeout: 30)
        guard let deviceOrientation = result["deviceOrientation"] as? String else { return nil }
        return PhysicalOrientation(
            deviceOrientation: deviceOrientation,
            nonFlat: result["deviceOrientationNonFlat"] as? String,
            isLocked: result["deviceIsOrientationLocked"] as? Bool
        )
    }

    // MARK: - Biometrics

    /// Enrollment state per biometric type (e.g. `["Face ID": false]`). An empty
    /// dictionary means the device advertises no biometric hardware.
    public static func biometricsEnrollment(udid: String) throws -> [String: Bool] {
        let result = try runJSON(["device", "settings", "biometrics", "--device", udid], timeout: 30)
        guard let entries = result["biometrics"] as? [[String: Any]] else { return [:] }
        var state: [String: Bool] = [:]
        for entry in entries {
            guard let type = entry["type"] as? String, let enabled = entry["enabled"] as? Bool else { continue }
            state[type] = enabled
        }
        return state
    }

    /// Enroll or unenroll every supported biometric type. Matching only takes
    /// effect while enrollment is on, so `simulateBiometrics` is a no-op without
    /// this.
    public static func setBiometricsEnrollment(udid: String, enabled: Bool) throws {
        try runChecked(
            ["device", "settings", "biometrics", "--device", udid, enabled ? "--enable" : "--disable"],
            timeout: 30
        )
    }

    /// Deliver a biometric match result to whatever is currently prompting
    /// (Face ID / Touch ID / Optic ID). Requires enrollment to be on.
    public static func simulateBiometrics(udid: String, success: Bool) throws {
        try runChecked(
            ["device", "simulate", "biometrics", "--device", udid, success ? "--success" : "--failure"],
            timeout: 30
        )
    }

    // MARK: - VoiceOver

    /// Whether VoiceOver is currently on, or nil when the runtime does not report it.
    public static func voiceOver(udid: String) throws -> Bool? {
        let result = try runJSON(["device", "info", "voiceover", "--device", udid], timeout: 30)
        return result["enabled"] as? Bool
    }

    /// Turn VoiceOver on or off. Driving VoiceOver navigation itself needs
    /// XCUITest's `XCUIVoiceOverService`; this controls the state an
    /// accessibility pass runs under.
    public static func setVoiceOver(udid: String, enabled: Bool) throws {
        try runChecked(
            ["device", "settings", "voiceover", "--device", udid, enabled ? "--enable" : "--disable"],
            timeout: 30
        )
    }

    // MARK: - Appearance / accessibility state

    /// Read the full appearance + accessibility state. Used both by
    /// `sipi appearance` and by the harness to capture a baseline it can
    /// restore after a run.
    public static func appearanceState(udid: String) throws -> AppearanceState {
        let result = try runJSON(["device", "info", "appearance", "--device", udid], timeout: 30)

        /// devicectl nests the toggles as `{ "enabled": Bool }` objects while
        /// reporting `increaseContrast` as a bare Bool. Accept both shapes so a
        /// future flattening does not silently read as "unsupported".
        func flag(_ key: String) -> Bool? {
            if let direct = result[key] as? Bool { return direct }
            if let nested = result[key] as? [String: Any] { return nested["enabled"] as? Bool }
            return nil
        }

        let colorFilter = result["colorFilter"] as? [String: Any]
        // devicectl nests the filter kind one level down and reports it in title
        // case ("Deuteranopia") while `settings appearance --color-filter-type`
        // only accepts lower case. Normalize on read so a captured state can be
        // written straight back.
        let filterType = (colorFilter?["filterType"] as? [String: Any])?["name"] as? String
            ?? colorFilter?["type"] as? String

        return AppearanceState(
            userInterfaceStyle: result["userInterfaceStyle"] as? String,
            lookAndFeel: result["lookAndFeel"] as? String,
            supportedLooksAndFeels: (result["supportedLooksAndFeels"] as? [String]) ?? [],
            textSize: result["textSize"] as? String,
            increaseContrast: flag("increaseContrast"),
            reduceMotion: flag("reduceMotion"),
            reduceTransparency: flag("reduceTransparency"),
            showBorders: flag("showBorders"),
            liquidGlassOpacity: result["liquidGlassOpacity"] as? Double,
            colorFilterEnabled: colorFilter?["enabled"] as? Bool,
            colorFilterType: filterType?.lowercased(),
            colorFilterIntensity: colorFilter?["intensity"] as? Double,
            largerAccessibilitySizes: result["largerAccessibilitySizesEnabled"] as? Bool
        )
    }

    /// Write one or more appearance facets in a single devicectl invocation.
    /// Passing an empty array is a no-op rather than a malformed command.
    public static func setAppearance(udid: String, settings: [AppearanceSetting]) throws {
        guard !settings.isEmpty else { return }
        let flags = settings.flatMap(\.arguments)
        try runChecked(["device", "settings", "appearance", "--device", udid] + flags, timeout: 30)
    }
}
