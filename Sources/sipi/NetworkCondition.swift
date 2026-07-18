import ArgumentParser
import Foundation
import SimShell

extension Sipi {
    struct NetworkCondition: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "network-condition",
            abstract: "Apply or clear a simulator-scoped network profile through an explicitly installed provider.",
            subcommands: [Status.self, Apply.self, Clear.self]
        )

        struct ProviderOptions: ParsableArguments {
            @Option(name: .long, help: "Absolute path to a provider executable. Defaults to SIPI_NETWORK_CONDITION_PROVIDER.")
            var provider: String?

            func resolve() throws -> NetworkConditionProvider {
                try NetworkConditionProvider.resolve(configuredPath: provider)
            }
        }

        struct Status: ParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "status",
                abstract: "Report whether an external provider is configured."
            )

            @OptionGroup var providerOptions: ProviderOptions

            func run() throws {
                do {
                    let provider = try providerOptions.resolve()
                    let raw = try provider.status().trimmingCharacters(in: .whitespacesAndNewlines)
                    let providerStatus: Any
                    if let data = raw.data(using: .utf8),
                       let object = try? JSONSerialization.jsonObject(with: data) {
                        providerStatus = object
                    } else {
                        providerStatus = raw
                    }
                    try writeJSON([
                        "available": true,
                        "provider": provider.executablePath,
                        "provider-status": providerStatus
                    ])
                } catch NetworkConditionProviderError.missingProvider {
                    try writeJSON([
                        "available": false,
                        "provider": NSNull(),
                        "reason": NetworkConditionProviderError.missingProvider.description
                    ])
                }
            }
        }

        struct Apply: ParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "apply",
                abstract: "Apply a provider-defined profile to one simulator app."
            )

            @Argument(help: "Provider profile id, in kebab-case (for example offline or packet-loss-100).")
            var profile: String

            @Argument(help: "Simulator UDID.")
            var udid: String

            @Option(name: .long, help: "Target app bundle identifier.")
            var bundleID: String

            @OptionGroup var providerOptions: ProviderOptions

            func run() throws {
                let provider = try providerOptions.resolve()
                try provider.apply(profile: profile, udid: udid, bundleID: bundleID)
                print("active profile=\(profile) udid=\(udid) bundle-id=\(bundleID)")
            }
        }

        struct Clear: ParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "clear",
                abstract: "Clear the active provider condition for one simulator app."
            )

            @Argument(help: "Simulator UDID.")
            var udid: String

            @Option(name: .long, help: "Target app bundle identifier.")
            var bundleID: String

            @OptionGroup var providerOptions: ProviderOptions

            func run() throws {
                let provider = try providerOptions.resolve()
                try provider.clear(udid: udid, bundleID: bundleID)
                print("inactive udid=\(udid) bundle-id=\(bundleID)")
            }
        }

        private static func writeJSON(_ object: [String: Any]) throws {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }
}
