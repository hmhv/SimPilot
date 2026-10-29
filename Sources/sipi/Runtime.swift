// Runtime.swift
//
// `sipi runtime list` — the simulator runtimes Apple offers, with the ones
// already installed marked. Neither xcodebuild nor simctl can list what is
// downloadable; Xcode itself reads this index.

import ArgumentParser
import Foundation

extension Sipi {
    struct RuntimeCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "runtime",
            abstract: "List simulator runtimes Apple offers.",
            subcommands: [List.self]
        )

        struct List: ParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "list",
                abstract: "List the simulator runtimes Apple offers, newest first, marking installed ones.",
                discussion: """
                Install one with `xcodebuild -downloadPlatform <platform> -buildVersion <version> -architectureVariant arm64`
                and remove one with `xcrun simctl runtime delete <identifier>`. Betas are hidden
                unless installed or --beta is passed.
                """
            )

            static let index = URL(string: "https://devimages-cdn.apple.com/downloads/xcode/simulators/index2.dvtdownloadableindex")!

            @Option(help: "iOS, watchOS, tvOS, or visionOS. All when omitted.")
            var platform: String?

            @Flag(help: "Include beta builds.")
            var beta = false

            func run() throws {
                let platforms = ["iOS": "iphoneos", "watchOS": "watchos", "tvOS": "appletvos", "visionOS": "xros"]
                if let platform, platforms[platform] == nil {
                    throw ValidationError("--platform must be one of iOS, watchOS, tvOS, visionOS")
                }
                guard let plist = try PropertyListSerialization.propertyList(from: HTTP.get(Self.index), format: nil) as? [String: Any],
                      let downloadables = plist["downloadables"] as? [[String: Any]]
                else { throw ValidationError("unexpected format at \(Self.index.absoluteString)") }

                let installed = installedBuilds()
                var seen = Set<String>()
                var rows: [(platform: String, version: String, build: String, line: String)] = []
                // The Apple-silicon-only image is smaller than the universal one.
                let byArchitectures = downloadables.sorted {
                    ($0["architectures"] as? [String])?.count ?? 1 < ($1["architectures"] as? [String])?.count ?? 1
                }
                for item in byArchitectures {
                    guard let rawPlatform = (item["platform"] as? String)?.replacingOccurrences(of: "com.apple.platform.", with: ""),
                          let name = platforms.first(where: { $0.value == rawPlatform })?.key,
                          platform.map({ $0 == name }) ?? true,
                          let simulator = item["simulatorVersion"] as? [String: Any],
                          let version = simulator["version"] as? String,
                          let build = simulator["buildUpdate"] as? String
                    else { continue }
                    let isInstalled = installed.contains(build)
                    guard beta || isInstalled || !Self.isBeta(build) else { continue }
                    let architectures = item["architectures"] as? [String]
                    guard architectures?.contains("arm64") ?? true, seen.insert("\(name) \(build)").inserted else { continue }
                    let size = String(format: "%.1f GB", Double(item["fileSize"] as? Int ?? 0) / 1_000_000_000)
                    let needs = item["hostRequirements"] as? [String: String]
                    let low = needs?["minXcodeVersion"], high = needs?["maxXcodeVersion"]
                    let only: String
                    if let low, low == high {
                        only = "  Xcode \(low) only"
                    } else if low != nil || high != nil {
                        only = "  Xcode " + [low.map { "\($0)+" }, high.map { "up to \($0)" }].compactMap { $0 }.joined(separator: ", ")
                    } else {
                        only = ""
                    }
                    let line = name.padding(toLength: 10, withPad: " ", startingAt: 0)
                        + version.padding(toLength: 8, withPad: " ", startingAt: 0)
                        + build.padding(toLength: 11, withPad: " ", startingAt: 0)
                        + size.padding(toLength: 9, withPad: " ", startingAt: 0)
                        + (isInstalled ? "installed" : "") + only
                    rows.append((name, version, build, line))
                }
                let newestFirst = rows.sorted {
                    if $0.platform != $1.platform { return $0.platform < $1.platform }
                    let order = $0.version.compare($1.version, options: .numeric)
                    return order == .orderedSame ? $0.build > $1.build : order == .orderedDescending
                }
                for row in newestFirst {
                    print(row.line)
                }
            }

            /// Beta builds end in a letter after four digits (24B5084k); releases
            /// do not (24B114, 23E254a).
            static func isBeta(_ build: String) -> Bool {
                build.range(of: "[0-9]{4}[a-z]$", options: .regularExpression) != nil
            }

            private func installedBuilds() -> Set<String> {
                // Without developer tools the xcrun shim opens an install dialog.
                guard systemDeveloperDir() != nil else { return [] }
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
                process.arguments = ["simctl", "runtime", "list", "-j"]
                let out = Pipe()
                process.standardOutput = out
                process.standardError = FileHandle.nullDevice
                guard (try? process.run()) != nil else { return [] }
                let data = out.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard let images = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return [] }
                return Set(images.values.compactMap { $0["build"] as? String })
            }
        }
    }
}
