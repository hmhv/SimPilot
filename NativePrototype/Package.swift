// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SimPilotBridge",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "sipi-bridge", targets: ["sipi-bridge"])
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
        // Headless CLI over the SimBridge core. The sipi-* skills call it from
        // Bash when AXe cannot inspect or drive System UI. No GUI.
        .executableTarget(
            name: "sipi-bridge",
            dependencies: ["SimBridge"],
            path: "Sources/sipi-bridge",
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
