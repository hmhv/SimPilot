// Perception.swift
//
// `sipi describe-ui`, `sipi describe-point`, and `sipi tap` — the native
// perception + selector-tap surface.
//
//   describe-ui    Default fast (frontmost+recursive). `--deep`
//                  forces the 16pt grid pass; `--expect "TEXT"` auto-triggers
//                  deep when the fast tree does not contain TEXT (this preserves
//                  the ui-driver.md `--expect` contract).
//   describe-point Single objectAtPoint hit-test at normalized 0...1 (nx, ny);
//                  no grid pass.
//   tap            `--label` / `--id` / `--value` resolve to an activation point
//                  via the SimCore resolver; or `-x`/`-y` for a direct point.
//
// All describe output is the SimCore describe-ui JSON contract (top-level array,
// spaced-colon pretty-print). HID taps go through the native driver in
// normalized 0...1, so logical activation points are normalized by the screen
// frame at the CLI boundary.

import ArgumentParser
import Foundation
import SimCore
import SimNative

/// Write a line to standard error (warnings / resolution failures).
func emitError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

/// The screen frame of an accessibility tree: the root node's frame, which is
/// the application / full-screen rectangle in logical points. Used to convert
/// between logical coordinates (the resolver / objectAtPoint space) and the
/// normalized 0...1 space the HID injector expects.
private func screenFrame(of roots: [AXNode]) -> AXNode.Frame? {
    roots.first { $0.type == "Application" }?.frame ?? roots.first?.frame
}

/// Normalize a logical point into 0...1 using a screen frame. Returns nil when
/// the frame has no positive extent (cannot normalize).
private func normalized(_ point: Point, in frame: AXNode.Frame) -> Point? {
    guard frame.width > 0, frame.height > 0 else { return nil }
    return Point(
        x: (point.x - frame.x) / frame.width,
        y: (point.y - frame.y) / frame.height
    )
}

/// The logical screen size (describe-ui root frame) for pixel->normalized
/// conversion in the direct-point `tap` path (Gate 4). Read via ChildTree, which
/// fetches in-process (repeated in-process fetches now return the full tree) and
/// falls back to a child process only if the in-process tree is degenerate.
private func tapScreenSize(udid: String) -> ScreenSize? {
    guard let roots = try? ChildTree.nodes(udid: udid, deep: false),
          let frame = screenFrame(of: roots),
          frame.width > 0, frame.height > 0 else { return nil }
    return ScreenSize(width: frame.width, height: frame.height)
}

/// A secondary describe-ui fetch (poll-after-action, `--expect` re-fetch,
/// selector deep-fallback, slider AXValue polling).
///
/// The AccessibilityPlatformTranslation bridge now returns the full tree on
/// EVERY in-process fetch (SimBridge keeps a stable per-device bridge-delegate
/// token, so its cached element stays resolvable — see SimBridge.m
/// `-stableTokenForDevice:udid:`). So this runs the fetch in-process and only
/// falls back to spawning a fresh child `sipi describe-ui` process if the
/// in-process result is unexpectedly degenerate. The child-process spawn stays
/// as a safety hedge: a fresh process always gets a clean first fetch, so a
/// surprise APT regression cannot break the flows that depend on this.
enum ChildTree {
    /// A serialized tree is "degenerate" when it is empty or a single root with
    /// no children and no label — the shape the pre-fix second in-process fetch
    /// produced. Used to decide whether to fall back to the child-process spawn.
    private static func isDegenerate(_ roots: [AXNode]) -> Bool {
        guard let root = roots.first, roots.count == 1 else { return roots.isEmpty }
        let label = root.AXLabel ?? ""
        return label.isEmpty && (root.children?.isEmpty ?? true)
    }

    /// The describe-ui JSON (top-level array, spaced colons) of the tree.
    /// In-process first, child-process spawn as a fallback hedge.
    static func json(udid: String, deep: Bool) throws -> String {
        let nodes = try nodes(udid: udid, deep: deep)
        return try AXNodeJSON.string(for: nodes)
    }

    /// The tree decoded into AXNodes (for selector resolution / frame lookup).
    /// Fetches in-process; if the in-process tree comes back degenerate, retries
    /// once in a fresh child process (which always gets a clean first fetch).
    static func nodes(udid: String, deep: Bool) throws -> [AXNode] {
        let inProcess = try NativeDriver().describe(udid, deep: deep)
        if !isDegenerate(inProcess) {
            return inProcess
        }
        emitError("[sipi] in-process describe-ui came back degenerate — retrying in a child process")
        return try spawnNodes(udid: udid, deep: deep)
    }

    /// The describe-ui JSON produced by a fresh child `sipi describe-ui` process.
    private static func spawnJSON(udid: String, deep: Bool) throws -> String {
        let process = Process()
        process.executableURL = executableURL()
        process.arguments = deep
            ? ["describe-ui", udid, "--deep"]
            : ["describe-ui", udid]

        let outPipe = Pipe()
        process.standardOutput = outPipe
        // Inherit stderr so child diagnostics surface alongside the parent's.
        try process.run()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return String(decoding: outData, as: UTF8.self)
            .trimmingCharacters(in: .newlines)
    }

    /// The child-process tree decoded back into AXNodes.
    private static func spawnNodes(udid: String, deep: Bool) throws -> [AXNode] {
        let data = Data(try spawnJSON(udid: udid, deep: deep).utf8)
        return try JSONDecoder().decode([AXNode].self, from: data)
    }

    /// The running `sipi` binary, resolved to an absolute path so the child can
    /// be spawned regardless of how the parent was invoked.
    private static func executableURL() -> URL {
        let arg0 = CommandLine.arguments[0]
        if arg0.hasPrefix("/") {
            return URL(fileURLWithPath: arg0)
        }
        let resolved = URL(fileURLWithPath: arg0, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        return resolved.standardizedFileURL
    }
}

// MARK: - describe-ui

extension Sipi {
    struct DescribeUI: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "describe-ui",
            abstract: "Print the accessibility tree as describe-ui JSON. Fast by default; --deep adds the grid pass."
        )

        @Argument(help: "Simulator UDID.")
        var udid: String

        @Flag(name: .long, help: "Force the full-screen grid pass (sees System UI; ~1.0s).")
        var deep = false

        @Option(name: .long, help: "Auto-trigger --deep when the fast tree does not contain this text.")
        var expect: String?

        func run() throws {
            let driver = NativeDriver()

            // Default fast (frontmost+recursive). `--deep` forces the grid pass;
            // `--expect` auto-triggers it when the fast tree misses the text.
            let nodes = try driver.describe(udid, deep: deep)
            let json = try AXNodeJSON.string(for: nodes)

            if !deep, let expect, !expect.isEmpty, !json.contains(expect) {
                emitError("[sipi] fast describe-ui missed expected text '\(expect)' — running --deep")
                print(try ChildTree.json(udid: udid, deep: true))
                return
            }

            print(json)
        }
    }
}

// MARK: - describe-point

extension Sipi {
    struct DescribePoint: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "describe-point",
            abstract: "Describe only the accessibility element at (x, y). Single objectAtPoint, no grid. Coordinates are --norm (default) or --pixel."
        )

        @OptionGroup var coordinate: CoordinateUnitOptions

        @Argument(help: "Simulator UDID.")
        var udid: String

        @Option(name: .customShort("x"), help: "X (normalized 0...1, or pixels with --pixel).")
        var x: Double

        @Option(name: .customShort("y"), help: "Y (normalized 0...1, or pixels with --pixel).")
        var y: Double

        func validate() throws {
            try coordinate.validate()
        }

        func run() throws {
            let driver = NativeDriver()

            // objectAtPoint works in the tree's logical coordinate space, so the
            // input is first standardized to normalized 0...1 (same Gate 4
            // convention as tap/swipe/touch), then converted to logical points
            // with the screen frame. The frame is read via ChildTree (in-process,
            // with a child-process fallback) before the `element(at:)` hit-test;
            // repeated in-process fetches now both return the full tree.
            let roots = try ChildTree.nodes(udid: udid, deep: false)
            guard let frame = screenFrame(of: roots) else {
                throw ValidationError("Could not determine the screen frame to convert coordinates.")
            }
            let screen = ScreenSize(width: frame.width, height: frame.height)
            let normalizedInput = try CoordinateConverter.normalize(
                x: x, y: y, unit: coordinate.unit, screen: screen
            )
            let logical = Point(
                x: frame.x + normalizedInput.x * frame.width,
                y: frame.y + normalizedInput.y * frame.height
            )

            let element = try driver.element(at: logical, udid: udid)
            let nodes = element.map { [$0] } ?? []
            let json = try AXNodeJSON.string(for: nodes)
            print(json)
        }
    }
}

// MARK: - tap

extension Sipi {
    struct Tap: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "tap",
            abstract: "Tap a point (--norm default or --pixel), or resolve --label/--id/--value to an activation point and tap it."
        )

        @OptionGroup var coordinate: CoordinateUnitOptions

        @Argument(help: "Simulator UDID.")
        var udid: String

        @Option(name: .customShort("x"), help: "X (normalized 0...1, or pixels with --pixel). Use with -y for a direct tap.")
        var x: Double?

        @Option(name: .customShort("y"), help: "Y (normalized 0...1, or pixels with --pixel). Use with -x for a direct tap.")
        var y: Double?

        @Option(name: .long, help: "Resolve and tap the element matching this AXLabel.")
        var label: String?

        @Option(name: .long, help: "Resolve and tap the element matching this AXUniqueId.")
        var id: String?

        @Option(name: .long, help: "Resolve and tap the element matching this AXValue.")
        var value: String?

        @Option(name: .customLong("element-type"), help: "Restrict --label/--id/--value matches to this accessibility type (e.g. Button, Switch).")
        var elementType: String?

        func validate() throws {
            try coordinate.validate()
            if x != nil || y != nil {
                guard x != nil, y != nil else {
                    throw ValidationError("Both -x and -y must be provided together.")
                }
                // Range is validated during conversion (Gate 4), which depends on
                // the unit and (for --pixel) the screen size resolved at run time.
            } else {
                let selectorCount = [label != nil, id != nil, value != nil].filter { $0 }.count
                if selectorCount == 0 {
                    throw ValidationError("Either provide both -x/-y, or use --label/--id/--value to tap an element.")
                }
                if selectorCount > 1 {
                    throw ValidationError("Use only one of --label, --id, or --value.")
                }
            }
        }

        func run() throws {
            let driver = NativeDriver()

            // Direct point — standardize to internal normalized 0...1 (Gate 4).
            if let x, let y {
                let screen = coordinate.unit == .pixel ? tapScreenSize(udid: udid) : nil
                let point = try CoordinateConverter.normalize(
                    x: x, y: y, unit: coordinate.unit, screen: screen
                )
                try driver.tap(point, udid: udid)
                print("ok")
                return
            }

            let query: AccessibilityQuery
            if let id {
                query = .id(id)
            } else if let label {
                query = .label(label)
            } else if let value {
                query = .value(value)
            } else {
                throw ValidationError("Either provide both -x/-y, or use --label/--id/--value to tap an element.")
            }

            // Resolve against the fast tree first; on a not-found, fall back to
            // the grid (deep) pass — the ui-driver.md keystone where a selector
            // that misses the frontmost tree is retried against System UI. The
            // deep pass goes through ChildTree (in-process, with a child-process
            // fallback); repeated in-process fetches now both return the full tree.
            var roots = try driver.describe(udid, deep: false)
            var resolution: TapResolution
            do {
                resolution = try AccessibilityTargetResolver.resolveTap(roots: roots, query: query, elementType: elementType)
            } catch let error as ElementResolutionError where error.isNotFound {
                roots = try ChildTree.nodes(udid: udid, deep: true)
                do {
                    resolution = try AccessibilityTargetResolver.resolveTap(roots: roots, query: query, elementType: elementType)
                } catch let retry as ElementResolutionError {
                    emitError("Warning: \(retry.description) No tap performed.")
                    throw ExitCode.failure
                }
            } catch let error as ElementResolutionError {
                emitError("Warning: \(error.description) No tap performed.")
                throw ExitCode.failure
            }

            guard let frame = screenFrame(of: roots) else {
                emitError("Warning: could not determine the screen frame to normalize the tap point. No tap performed.")
                throw ExitCode.failure
            }
            guard let normalizedPoint = normalized(resolution.point, in: frame) else {
                emitError("Warning: screen frame has no positive extent; cannot normalize the tap point. No tap performed.")
                throw ExitCode.failure
            }

            try driver.tap(normalizedPoint, udid: udid)
            print("ok")
        }
    }
}
