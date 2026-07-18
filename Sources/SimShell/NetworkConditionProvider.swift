import Foundation

public enum NetworkConditionProviderError: Error, CustomStringConvertible {
    case missingProvider
    case providerMustBeAbsolute(String)
    case providerNotExecutable(String)
    case invalidProfile(String)
    case launchFailed(String)
    case commandFailed(code: Int32, stderr: String)

    public var description: String {
        switch self {
        case .missingProvider:
            return "No simulator network-condition provider is configured. Set network-condition-provider in .simpilot/config.json or SIPI_NETWORK_CONDITION_PROVIDER. SimPilot does not assume a built-in simctl network-condition command."
        case .providerMustBeAbsolute(let path):
            return "network-condition provider path must be absolute: \(path)"
        case .providerNotExecutable(let path):
            return "network-condition provider is not executable: \(path)"
        case .invalidProfile(let profile):
            return "network-condition profile must be kebab-case: \(profile)"
        case .launchFailed(let message):
            return "failed to launch network-condition provider: \(message)"
        case .commandFailed(let code, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "network-condition provider exited \(code)\(detail.isEmpty ? "" : ": \(detail)")"
        }
    }
}

/// Adapter for an explicitly installed simulator-scoped network conditioner.
/// SimPilot intentionally ships no packet filter or proprietary integration.
/// A provider receives a small argv-only contract and owns the actual filtering.
public struct NetworkConditionProvider: Sendable {
    public let executablePath: String

    public init(path: String) throws {
        guard path.hasPrefix("/") else {
            throw NetworkConditionProviderError.providerMustBeAbsolute(path)
        }
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw NetworkConditionProviderError.providerNotExecutable(path)
        }
        self.executablePath = path
    }

    public static func resolve(configuredPath: String? = nil) throws -> NetworkConditionProvider {
        let environmentPath = ProcessInfo.processInfo.environment["SIPI_NETWORK_CONDITION_PROVIDER"]
        guard let path = configuredPath ?? environmentPath, !path.isEmpty else {
            throw NetworkConditionProviderError.missingProvider
        }
        return try NetworkConditionProvider(path: path)
    }

    public func status() throws -> String {
        try run(["status", "--json"])
    }

    public func apply(profile: String, udid: String, bundleID: String) throws {
        guard Self.isKebabCase(profile) else {
            throw NetworkConditionProviderError.invalidProfile(profile)
        }
        _ = try run([
            "apply",
            "--udid", udid,
            "--bundle-id", bundleID,
            "--profile", profile
        ])
    }

    public func clear(udid: String, bundleID: String) throws {
        _ = try run([
            "clear",
            "--udid", udid,
            "--bundle-id", bundleID
        ])
    }

    private func run(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            throw NetworkConditionProviderError.launchFailed(error.localizedDescription)
        }
        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NetworkConditionProviderError.commandFailed(
                code: process.terminationStatus,
                stderr: String(decoding: errorData, as: UTF8.self)
            )
        }
        return String(decoding: outputData, as: UTF8.self)
    }

    private static func isKebabCase(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 64 else { return false }
        return value.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) != nil
    }
}
