// Input.swift
//
// `sipi` input surface. Mirrors AXe's input commands on top of the native
// driver:
//
//   type           Map US-keyboard chars -> HID via SimCore TextToHIDEvents and
//                  inject them. Non-US text falls back to `simctl pbcopy` + Cmd+V
//                  (requires the field to be focused first; clobbers + restores
//                  the simulator pasteboard — see §6.10). `--stdin` / `--file`.
//   key            Press one HID keycode (optionally held for --duration).
//   key-sequence   Press a comma-separated list of keycodes in order.
//   key-combo      Hold modifiers, press the key, release modifiers in LIFO order.
//   swipe          a -> b with --duration and a --delta-derived step count.
//   touch          down / up / long-press (down -> hold -> up).
//   drag           Composite point-to-point drag with explicit moves.
//   gesture        Directional / scroll presets over the swipe primitive.
//   slider         Resolve a slider, drag to a target value, poll AXValue.
//
// COORDINATE UNITS (Gate 4): tap (in Perception.swift), swipe, touch, drag, and
// describe-point all take `--pixel` / `--norm`; pixel inputs are converted to the
// internal normalized 0...1 with the logical screen size and validated so a pixel
// value can never be silently treated as a top-left normalized tap.

import ArgumentParser
import Foundation
import SimCore
import SimNative
import SimShell

// MARK: - Coordinate-unit flags (Gate 4)

/// Shared `--pixel` / `--norm` flags. Default is `--norm` (the internal
/// representation); `--pixel` converts logical pixels with the screen size.
struct CoordinateUnitOptions: ParsableArguments {
    @Flag(name: .long, help: "Interpret coordinates as logical screen pixels (converted with the screen size).")
    var pixel = false

    @Flag(name: .long, help: "Interpret coordinates as normalized 0...1 (the default).")
    var norm = false

    func validate() throws {
        if pixel && norm {
            throw ValidationError("Use only one of --pixel or --norm.")
        }
    }

    var unit: CoordinateUnit { pixel ? .pixel : .norm }
}

/// Resolve the logical screen size (describe-ui root frame) for pixel->normalized
/// conversion. Goes through ChildTree (in-process, with a child-process
/// fallback); repeated in-process fetches now both return the full tree. Returns
/// nil when no usable frame is found; callers using `--norm` never need it.
private func resolveScreenSize(udid: String) -> ScreenSize? {
    guard let roots = try? ChildTree.nodes(udid: udid, deep: false) else { return nil }
    let frame = roots.first { $0.type == "Application" }?.frame ?? roots.first?.frame
    guard let frame, frame.width > 0, frame.height > 0 else { return nil }
    return ScreenSize(width: frame.width, height: frame.height)
}

/// Convert a CLI coordinate pair to the internal normalized Point, resolving the
/// screen size lazily only when `--pixel` is in effect. Shared by the input
/// commands here and `multitouch` (MultiTouchCrown.swift).
func normalizedPoint(
    x: Double,
    y: Double,
    unit: CoordinateUnit,
    udid: String
) throws -> Point {
    let screen = unit == .pixel ? resolveScreenSize(udid: udid) : nil
    return try CoordinateConverter.normalize(x: x, y: y, unit: unit, screen: screen)
}

// MARK: - type

extension Sipi {
    struct TypeText: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "type",
            abstract: "Type text into the focused field via HID; non-US text pastes via the pasteboard.",
            discussion: """
            Input sources (exactly one): a positional text argument, --stdin, or --file.

            US-keyboard characters (A-Z a-z 0-9 and !@#$%^&*()_+-={}[]|\\:";'<>?,./`~)
            are injected directly as HID key events. Any text containing other
            characters (accented letters, non-Latin scripts, emoji) falls back to
            copying the text onto the simulator pasteboard and pressing Cmd+V.

            The paste fallback pastes into the FIRST RESPONDER, so the target field
            must already be focused (tap it first). It CLOBBERS the simulator
            pasteboard; sipi saves the prior contents and restores them afterward
            on a best-effort basis.
            """
        )

        @Argument(help: "Simulator UDID.")
        var udid: String

        @Argument(help: "The text to type. Quote text with spaces/special characters. Omit when using --stdin or --file.")
        var text: String?

        @Flag(name: .customLong("stdin"), help: "Read the text from standard input.")
        var useStdin = false

        @Option(name: .customLong("file"), help: "Read the text from this file.")
        var inputFile: String?

        func validate() throws {
            let sources = [text != nil, useStdin, inputFile != nil].filter { $0 }.count
            if sources > 1 {
                throw ValidationError("Provide only one input source: a text argument, --stdin, or --file.")
            }
            if sources == 0 {
                throw ValidationError("No input provided. Pass text as an argument, or use --stdin or --file.")
            }
        }

        func run() throws {
            let inputText: String
            if let text {
                inputText = text
            } else if useStdin {
                inputText = readStdin()
            } else if let inputFile {
                do {
                    inputText = try String(contentsOfFile: inputFile, encoding: .utf8)
                } catch {
                    throw ValidationError("Failed to read file '\(inputFile)': \(error.localizedDescription)")
                }
            } else {
                throw ValidationError("No input provided.")
            }

            let driver = NativeDriver()

            if TextToHIDEvents.validateText(inputText) {
                let events = try TextToHIDEvents.convertTextToHIDEvents(inputText)
                for event in events {
                    try driver.key(usage: event.usage, down: event.down, udid: udid)
                    // Pace the events: sent back-to-back with no gap, the guest
                    // keyboard coalesces and drops trailing characters (e.g.
                    // "hello" lands as "hel"). A short inter-event delay lets each
                    // keystroke register while staying fast for normal-length text.
                    usleep(12 * 1000)
                }
                print("ok")
                return
            }

            // Non-US path: paste via the simulator pasteboard + Cmd+V. The field
            // must already be focused; we clobber the pasteboard, so save and
            // restore the prior contents on a best-effort basis (§6.10).
            emitError("[sipi] text contains non-US characters; pasting via the simulator pasteboard (the field must be focused; the pasteboard is clobbered and restored).")

            let saved = try? SimShell.pbpaste(udid: udid)
            do {
                try SimShell.pbcopy(inputText, udid: udid)
            } catch {
                throw ValidationError("Failed to copy text onto the simulator pasteboard: \(error.localizedDescription)")
            }

            for event in KeyInput.pasteCombo() {
                try driver.key(usage: event.usage, down: event.down, udid: udid)
            }

            if let saved {
                // Best-effort restore of the user's prior pasteboard.
                try? SimShell.pbcopy(saved, udid: udid)
            }
            print("ok")
        }

        private func readStdin() -> String {
            var input = ""
            while let line = readLine(strippingNewline: false) {
                input += line
            }
            return input
        }
    }
}

// MARK: - key

extension Sipi {
    struct Key: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "key",
            abstract: "Press a single key by HID keycode (e.g. 40 = Return, 42 = Backspace)."
        )

        @Argument(help: "The HID keycode to press (0...255).")
        var keycode: Int

        @Argument(help: "Simulator UDID.")
        var udid: String

        @Option(name: .long, help: "Seconds to hold the key (0 < duration <= 10).")
        var duration: Double?

        func validate() throws {
            guard (0...255).contains(keycode) else {
                throw ValidationError("Keycode must be between 0 and 255.")
            }
            if let duration {
                guard duration > 0, duration <= 10 else {
                    throw ValidationError("Duration must be greater than 0 and at most 10 seconds.")
                }
            }
        }

        func run() throws {
            let driver = NativeDriver()
            try driver.key(usage: keycode, down: true, udid: udid)
            if let duration {
                usleep(useconds_t(duration * 1_000_000))
            }
            try driver.key(usage: keycode, down: false, udid: udid)
            print("ok")
        }
    }
}

// MARK: - key-sequence

extension Sipi {
    struct KeySequence: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "key-sequence",
            abstract: "Press a comma-separated list of HID keycodes in order (each pressed and released)."
        )

        @Option(name: .customLong("keycodes"), help: "Comma-separated HID keycodes, e.g. 11,8,15,15,18.")
        var keycodesString: String

        @Argument(help: "Simulator UDID.")
        var udid: String

        @Option(name: .long, help: "Seconds between key presses (default: 0.1).")
        var delay: Double?

        func validate() throws {
            let codes = try parseKeycodes(keycodesString)
            guard !codes.isEmpty else {
                throw ValidationError("At least one keycode must be provided.")
            }
            guard codes.count <= 100 else {
                throw ValidationError("Key sequence must not exceed 100 keys.")
            }
            for code in codes {
                guard (0...255).contains(code) else {
                    throw ValidationError("All keycodes must be between 0 and 255. Invalid keycode: \(code)")
                }
            }
            if let delay {
                guard delay >= 0, delay <= 5 else {
                    throw ValidationError("Delay must be between 0 and 5 seconds.")
                }
            }
        }

        func run() throws {
            let driver = NativeDriver()
            let codes = try parseKeycodes(keycodesString)
            let keyDelay = delay ?? 0.1

            for (index, code) in codes.enumerated() {
                try driver.key(usage: code, down: true, udid: udid)
                try driver.key(usage: code, down: false, udid: udid)
                if index < codes.count - 1, keyDelay > 0 {
                    usleep(useconds_t(keyDelay * 1_000_000))
                }
            }
            print("ok")
        }
    }
}

// MARK: - key-combo

extension Sipi {
    struct KeyCombo: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "key-combo",
            abstract: "Hold modifier keycodes, press a key, release modifiers in LIFO order (e.g. Cmd+V)."
        )

        @Option(name: .customLong("modifiers"), help: "Comma-separated modifier keycodes to hold, e.g. 227 (Cmd) or 227,225 (Cmd+Shift).")
        var modifiersString: String

        @Option(name: .customLong("key"), help: "The HID keycode to press while modifiers are held (0...255).")
        var key: Int

        @Argument(help: "Simulator UDID.")
        var udid: String

        func validate() throws {
            let modifiers = try parseKeycodes(modifiersString)
            guard !modifiers.isEmpty else {
                throw ValidationError("At least one modifier keycode must be provided.")
            }
            guard modifiers.count <= 8 else {
                throw ValidationError("At most 8 modifier keycodes may be provided.")
            }
            for code in modifiers {
                guard (0...255).contains(code) else {
                    throw ValidationError("All modifier keycodes must be between 0 and 255. Invalid keycode: \(code)")
                }
            }
            guard (0...255).contains(key) else {
                throw ValidationError("Key must be between 0 and 255.")
            }
        }

        func run() throws {
            let driver = NativeDriver()
            let modifiers = try parseKeycodes(modifiersString)
            for event in KeyInput.keyCombo(modifiers: modifiers, key: key) {
                try driver.key(usage: event.usage, down: event.down, udid: udid)
            }
            print("ok")
        }
    }
}

// MARK: - swipe

extension Sipi {
    struct Swipe: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "swipe",
            abstract: "Swipe from a start point to an end point over a duration. Coordinates are --norm (default) or --pixel."
        )

        @OptionGroup var coordinate: CoordinateUnitOptions

        @Argument(help: "Simulator UDID.")
        var udid: String

        @Option(name: .customLong("start-x"), help: "Start X (normalized 0...1, or pixels with --pixel).")
        var startX: Double

        @Option(name: .customLong("start-y"), help: "Start Y (normalized 0...1, or pixels with --pixel).")
        var startY: Double

        @Option(name: .customLong("end-x"), help: "End X (normalized 0...1, or pixels with --pixel).")
        var endX: Double

        @Option(name: .customLong("end-y"), help: "End Y (normalized 0...1, or pixels with --pixel).")
        var endY: Double

        @Option(name: .long, help: "Duration of the swipe in seconds (default: 0.3).")
        var duration: Double?

        func validate() throws {
            try coordinate.validate()
            guard startX != endX || startY != endY else {
                throw ValidationError("Start and end points must be different.")
            }
            if let duration {
                guard duration > 0, duration <= 10 else {
                    throw ValidationError("Duration must be greater than 0 and at most 10 seconds.")
                }
            }
        }

        func run() throws {
            let driver = NativeDriver()
            let start = try normalizedPoint(x: startX, y: startY, unit: coordinate.unit, udid: udid)
            let end = try normalizedPoint(x: endX, y: endY, unit: coordinate.unit, udid: udid)
            try driver.swipe(start, end, duration: duration ?? 0.3, udid: udid)
            print("ok")
        }
    }
}

// MARK: - touch

extension Sipi {
    struct Touch: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "touch",
            abstract: "Low-level touch down/up at a point; --down --up with --delay is a long-press. Coordinates are --norm (default) or --pixel."
        )

        @OptionGroup var coordinate: CoordinateUnitOptions

        @Argument(help: "Simulator UDID.")
        var udid: String

        @Option(name: .customShort("x"), help: "X (normalized 0...1, or pixels with --pixel).")
        var x: Double

        @Option(name: .customShort("y"), help: "Y (normalized 0...1, or pixels with --pixel).")
        var y: Double

        @Flag(name: .customLong("down"), help: "Perform a touch-down.")
        var down = false

        @Flag(name: .customLong("up"), help: "Perform a touch-up.")
        var up = false

        @Option(name: .long, help: "Seconds to hold between down and up (long-press; requires both --down and --up).")
        var delay: Double?

        func validate() throws {
            try coordinate.validate()
            guard down || up else {
                throw ValidationError("Specify at least one of --down or --up.")
            }
            if let delay {
                guard delay >= 0, delay <= 10 else {
                    throw ValidationError("Delay must be between 0 and 10 seconds.")
                }
                guard down && up else {
                    throw ValidationError("--delay can only be used when both --down and --up are specified.")
                }
            }
        }

        func run() throws {
            let driver = NativeDriver()
            let point = try normalizedPoint(x: x, y: y, unit: coordinate.unit, udid: udid)

            if down && up {
                // Long-press: down -> hold -> up so iOS recognizers observe a real
                // hold duration. Default hold matches AXe's tap timing (0.1s).
                try driver.longPress(point, hold: delay ?? 0.1, udid: udid)
            } else if down {
                try driver.touch(point, phase: .begin, udid: udid)
            } else {
                try driver.touch(point, phase: .end, udid: udid)
            }
            print("ok")
        }
    }
}

// MARK: - drag

extension Sipi {
    struct Drag: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "drag",
            abstract: "Composite point-to-point drag with explicit interpolated moves. Coordinates are --norm (default) or --pixel."
        )

        @OptionGroup var coordinate: CoordinateUnitOptions

        @Argument(help: "Simulator UDID.")
        var udid: String

        @Option(name: .customLong("start-x"), help: "Start X (normalized 0...1, or pixels with --pixel).")
        var startX: Double

        @Option(name: .customLong("start-y"), help: "Start Y (normalized 0...1, or pixels with --pixel).")
        var startY: Double

        @Option(name: .customLong("end-x"), help: "End X (normalized 0...1, or pixels with --pixel).")
        var endX: Double

        @Option(name: .customLong("end-y"), help: "End Y (normalized 0...1, or pixels with --pixel).")
        var endY: Double

        @Option(name: .long, help: "Duration of the drag in seconds (default: 0.6).")
        var duration: Double = 0.6

        @Option(name: .long, help: "Number of interpolated touch-move events (default: 60).")
        var steps: Int = 60

        func validate() throws {
            try coordinate.validate()
            guard startX != endX || startY != endY else {
                throw ValidationError("Start and end points must be different.")
            }
            guard duration > 0 else {
                throw ValidationError("Duration must be greater than 0.")
            }
            guard (1...1000).contains(steps) else {
                throw ValidationError("Steps must be between 1 and 1000.")
            }
        }

        func run() throws {
            let driver = NativeDriver()
            let start = try normalizedPoint(x: startX, y: startY, unit: coordinate.unit, udid: udid)
            let end = try normalizedPoint(x: endX, y: endY, unit: coordinate.unit, udid: udid)
            try driver.compositeDrag(
                from: start,
                to: end,
                duration: duration,
                steps: steps,
                initialHold: 0.05,
                finalHold: 0.05,
                udid: udid
            )
            print("ok")
        }
    }
}

// MARK: - gesture

extension Sipi {
    struct Gesture: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "gesture",
            abstract: "Perform a preset gesture (scroll-up/down/left/right, swipe-from-*-edge) over the swipe primitive."
        )

        @Argument(help: "The gesture preset: scroll-up | scroll-down | scroll-left | scroll-right | swipe-from-left-edge | swipe-from-right-edge | swipe-from-top-edge | swipe-from-bottom-edge.")
        var preset: String

        @Argument(help: "Simulator UDID.")
        var udid: String

        @Option(name: .long, help: "Duration of the gesture in seconds (uses the preset default if omitted).")
        var duration: Double?

        func validate() throws {
            guard GesturePreset(rawValue: preset) != nil else {
                let valid = GesturePreset.allCases.map(\.rawValue).joined(separator: ", ")
                throw ValidationError("Unknown gesture preset '\(preset)'. Valid presets: \(valid).")
            }
            if let duration {
                guard duration > 0, duration <= 10 else {
                    throw ValidationError("Duration must be greater than 0 and at most 10 seconds.")
                }
            }
        }

        func run() throws {
            guard let gesture = GesturePreset(rawValue: preset) else {
                throw ValidationError("Unknown gesture preset '\(preset)'.")
            }
            let driver = NativeDriver()
            let endpoints = gesture.normalizedEndpoints()
            try driver.swipe(
                endpoints.start,
                endpoints.end,
                duration: duration ?? gesture.defaultDuration,
                udid: udid
            )
            print("ok")
        }
    }
}

// MARK: - slider

extension Sipi {
    struct SliderSet: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "slider",
            abstract: "Set a slider to a value (0...100): resolve it, drag the thumb, then poll AXValue to verify."
        )

        @Argument(help: "Simulator UDID.")
        var udid: String

        @Option(name: .long, help: "Resolve the slider matching this AXUniqueId.")
        var id: String?

        @Option(name: .long, help: "Resolve the slider matching this AXLabel.")
        var label: String?

        @Option(name: .customLong("element-type"), help: "Restrict matches to this accessibility type (usually Slider).")
        var elementType: String?

        @Option(name: .long, help: "Target slider value as a percentage 0...100.")
        var value: Double

        @Option(name: .long, help: "Accepted value tolerance, normalized 0...1 (default: 0.02 = +-2%).")
        var tolerance: Double?

        func validate() throws {
            let selectors = [id != nil, label != nil].filter { $0 }.count
            guard selectors == 1 else {
                throw ValidationError("Use exactly one of --id or --label to target a slider.")
            }
            if let id, id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ValidationError("--id must not be empty.")
            }
            if let label, label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ValidationError("--label must not be empty.")
            }
            guard value.isFinite, (0...100).contains(value) else {
                throw ValidationError("--value must be a finite number between 0 and 100.")
            }
            if let tolerance {
                guard tolerance > 0, tolerance <= 1 else {
                    throw ValidationError("--tolerance must be greater than 0 and at most 1.")
                }
            }
        }

        func run() throws {
            let driver = NativeDriver()
            let query: AccessibilityQuery = id.map { AccessibilityQuery.id($0) }
                ?? .label(label!)
            let targetNormalized = value / 100.0
            let tol = tolerance ?? SliderPlan.valueTolerance

            // Resolve against the fast tree, then deep (System UI) on a not-found.
            let roots = try resolveRoots(driver: driver, query: query)
            let match: AccessibilityMatch
            do {
                match = try AccessibilityTargetResolver.resolveElement(
                    roots: roots,
                    query: query,
                    elementType: elementType
                )
            } catch let error as ElementResolutionError {
                emitError("Warning: \(error.description) No slider set.")
                throw ExitCode.failure
            }

            let plan: SliderPlan.DragPlan
            do {
                plan = try SliderPlan.makeDragPlan(
                    element: match.element,
                    applicationFrame: match.applicationFrame,
                    targetNormalized: targetNormalized,
                    tolerance: tol
                )
            } catch let error as SliderPlan.SliderError {
                emitError("Warning: \(error.description)")
                throw ExitCode.failure
            }

            guard let screen = screenSizeFor(roots: roots) else {
                emitError("Warning: could not determine the screen size to drive the slider drag.")
                throw ExitCode.failure
            }

            if !plan.alreadyAtTarget {
                let start = Point(x: plan.logicalStart.x / screen.width, y: plan.logicalStart.y / screen.height)
                let end = Point(x: plan.logicalEnd.x / screen.width, y: plan.logicalEnd.y / screen.height)
                try driver.compositeDrag(
                    from: clamp01(start),
                    to: clamp01(end),
                    duration: SliderPlan.dragDuration,
                    steps: SliderPlan.dragSteps,
                    initialHold: SliderPlan.dragInitialHold,
                    finalHold: SliderPlan.dragFinalHold,
                    udid: udid
                )
            }

            // Verify by polling AXValue. Each read goes through ChildTree
            // (in-process, with a child-process fallback); repeated in-process
            // fetches now each return the full tree, so the poll loop no longer
            // pays the cost of spawning a process per iteration.
            let observed = try pollObservedValue(
                query: query,
                targetNormalized: targetNormalized,
                tolerance: tol
            )

            guard let observed, SliderPlan.isWithinTolerance(observed: observed.normalized, target: targetNormalized, tolerance: tol) else {
                emitError("Warning: \(SliderPlan.SliderError.notReached(target: targetNormalized, observed: observed?.raw).description)")
                throw ExitCode.failure
            }
            print("Slider set to \(SliderPlan.formatPercent(value)) (AXValue: \(observed.raw ?? SliderPlan.formatNormalized(observed.normalized)))")
        }

        // MARK: helpers

        private struct Observed {
            let raw: String?
            let normalized: Double
        }

        /// Resolve against the fast tree, falling back to the deep (grid / System
        /// UI) pass via ChildTree (in-process, with a child-process fallback) on a
        /// not-found.
        private func resolveRoots(driver: NativeDriver, query: AccessibilityQuery) throws -> [AXNode] {
            let fast = try driver.describe(udid, deep: false)
            do {
                _ = try AccessibilityTargetResolver.resolveElement(roots: fast, query: query, elementType: elementType)
                return fast
            } catch let error as ElementResolutionError where error.isNotFound {
                return try ChildTree.nodes(udid: udid, deep: true)
            }
        }

        private func screenSizeFor(roots: [AXNode]) -> ScreenSize? {
            let frame = roots.first { $0.type == "Application" }?.frame ?? roots.first?.frame
            guard let frame, frame.width > 0, frame.height > 0 else { return nil }
            return ScreenSize(width: frame.width, height: frame.height)
        }

        private func clamp01(_ p: Point) -> Point {
            Point(x: min(max(p.x, 0), 1), y: min(max(p.y, 0), 1))
        }

        private func pollObservedValue(
            query: AccessibilityQuery,
            targetNormalized: Double,
            tolerance: Double
        ) throws -> Observed? {
            let deadline = Date().addingTimeInterval(SliderPlan.verificationTimeout)
            var last: Observed?

            repeat {
                let roots = try ChildTree.nodes(udid: udid, deep: false)
                if let match = try? AccessibilityTargetResolver.resolveElement(roots: roots, query: query, elementType: elementType),
                   let normalized = try? SliderPlan.parseNormalizedAXValue(match.element.AXValue) {
                    let observed = Observed(raw: match.element.AXValue, normalized: normalized)
                    last = observed
                    if SliderPlan.isWithinTolerance(observed: normalized, target: targetNormalized, tolerance: tolerance) {
                        // Settle, then confirm stability once.
                        usleep(useconds_t(SliderPlan.verificationStabilityDelay * 1_000_000))
                        if Date() >= deadline { return observed }
                        if let stable = try? ChildTree.nodes(udid: udid, deep: false),
                           let stableMatch = try? AccessibilityTargetResolver.resolveElement(roots: stable, query: query, elementType: elementType),
                           let stableNormalized = try? SliderPlan.parseNormalizedAXValue(stableMatch.element.AXValue) {
                            let stableObserved = Observed(raw: stableMatch.element.AXValue, normalized: stableNormalized)
                            if SliderPlan.isWithinTolerance(observed: stableNormalized, target: targetNormalized, tolerance: tolerance) {
                                return stableObserved
                            }
                            last = stableObserved
                        }
                    }
                }
                if Date() < deadline {
                    usleep(useconds_t(SliderPlan.verificationPollInterval * 1_000_000))
                }
            } while Date() < deadline

            return last
        }
    }
}

// MARK: - shared keycode parsing

/// Parse a comma-separated list of integers, rejecting empty / non-numeric
/// entries. Mirrors AXe's `parseCommaSeparatedIntsStrict`.
func parseKeycodes(_ raw: String) throws -> [Int] {
    let trimmed = raw.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return [] }
    return try trimmed.split(separator: ",", omittingEmptySubsequences: false).map { piece in
        let token = piece.trimmingCharacters(in: .whitespaces)
        guard let value = Int(token) else {
            throw ValidationError("Invalid keycode '\(token)'. Provide comma-separated integers (0...255).")
        }
        return value
    }
}
