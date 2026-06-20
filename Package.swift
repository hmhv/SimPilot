// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SimPilotBridge",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "sipi", targets: ["sipi"]),
        .library(name: "SimCore", targets: ["SimCore"]),
        .library(name: "SimNative", targets: ["SimNative"]),
        .library(name: "SimShell", targets: ["SimShell"]),
        .library(name: "SimSkills", targets: ["SimSkills"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")
    ],
    targets: [
        // Objective-C bridge into Apple's private Simulator frameworks
        // (CoreSimulator + AccessibilityPlatformTranslation). Loaded at runtime
        // via dlopen — no build-time linkage to private frameworks.
        .target(
            name: "SimBridge",
            path: "Sources/SimBridge",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("IOSurface"),
                .linkedFramework("CoreImage"),
                .linkedFramework("CoreVideo")
            ]
        ),
        // The three skill trees (sipi-common, sipi-test, sipi-verify) embedded
        // into the binary at build time so the curl|bash install ships a single
        // self-contained download. The EmbedSkillsPlugin build-tool plugin runs
        // simskillsgen on every `swift build`, reading the real skill files via
        // the in-package `skills` symlink (-> ../.claude/skills) and generating
        // EmbeddedSkillsData.swift. The symlink is excluded from the compiled
        // sources; only the hand-written EmbeddedSkills.swift API surface is.
        .target(
            name: "SimSkills",
            path: "Sources/SimSkills",
            exclude: ["skills"],
            sources: ["EmbeddedSkills.swift"],
            plugins: ["EmbedSkillsPlugin"]
        ),
        // Build-time generator that walks the skill trees and emits
        // EmbeddedSkillsData.swift (base64 file bytes + executable bits). Run by
        // the EmbedSkillsPlugin; not part of the shipped binary.
        .executableTarget(
            name: "simskillsgen",
            path: "Sources/simskillsgen"
        ),
        // Regenerates the embedded-skills data on every build of SimSkills so it
        // can never go stale relative to .claude/skills.
        .plugin(
            name: "EmbedSkillsPlugin",
            capability: .buildTool(),
            dependencies: ["simskillsgen"],
            path: "Plugins/EmbedSkillsPlugin"
        ),
        // Pure Foundation library. No SimBridge import, no Process(), no private
        // frameworks. Holds the framework-agnostic SimDriver seam and value
        // types so SimCore stays unit-testable with a mock driver and a future
        // FB backend can be added behind the same protocol. Depends on SimSkills
        // so the embedded skill payload is available to setup/update flows.
        .target(
            name: "SimCore",
            dependencies: ["SimSkills"],
            path: "Sources/SimCore"
        ),
        // Contract tests for the SimCore describe-ui JSON encoder. Hand-built
        // fixture trees only — no simulator, no SimBridge. Locks the §4.2
        // verify-form and structural-shape assertions.
        .testTarget(
            name: "SimCoreTests",
            dependencies: ["SimCore", "SimSkills"],
            path: "Tests/SimCoreTests"
        ),
        // The one SimDriver implementation today. Wires SimCore value types to
        // the existing SimBridge (CSimBridge) ObjC APIs.
        .target(
            name: "SimNative",
            dependencies: ["SimCore", "SimBridge"],
            path: "Sources/SimNative",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("IOSurface"),
                .linkedFramework("CoreImage"),
                .linkedFramework("CoreVideo")
            ]
        ),
        // Gated integration test for the in-process AccessibilityPlatformTranslation
        // path. Needs a booted simulator, so every test no-ops unless
        // SIPI_TEST_UDID is set to a booted UDID. Locks the stable-token fix:
        // repeated in-process AX fetches must each return the full tree (not a
        // degenerate root). Depends on SimNative + SimBridge, kept out of the
        // pure SimCoreTests target so that stays simulator-free.
        .testTarget(
            name: "SimNativeIntegrationTests",
            dependencies: ["SimNative", "SimCore"],
            path: "Tests/SimNativeIntegrationTests",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("IOSurface"),
                .linkedFramework("CoreImage"),
                .linkedFramework("CoreVideo")
            ]
        ),
        // Pure Foundation typed Process() wrappers over public `xcrun simctl`
        // for app/file/lifecycle facets that never touch private frameworks.
        .target(
            name: "SimShell",
            path: "Sources/SimShell"
        ),
        // Umbrella CLI; the sole native simulator driver for the package.
        .executableTarget(
            name: "sipi",
            dependencies: [
                "SimCore",
                "SimNative",
                "SimShell",
                "SimBridge",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/sipi",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("IOSurface"),
                .linkedFramework("CoreImage"),
                .linkedFramework("CoreVideo")
            ]
        )
    ]
)
