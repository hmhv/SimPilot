// NativeDriver.swift
//
// The one SimDriver implementation today. Wires SimCore value types to the
// existing SimBridge (CSimBridge) ObjC APIs (SPSimBridge). All dlopen paths and
// magic HID constants live in SimBridge; this layer is plain Swift glue.
//
// Stage M0 wires only what SimBridge exposes today: devices(), screenshot(to:),
// tap(_:), key(...), button(...). describe()/element(at:)/swipe()/
// uiOrientation() throw SimDriverError.notImplemented until later stages.

import Foundation
import SimCore
import SimBridge

public final class NativeDriver: SimDriver {
    private let developerDir: String

    /// Test-only instrumentation: invoked once each time a gesture resolves its
    /// orientation + logical extent up front (see `resolvePhysicalContext`).
    /// `OrientationTapWiringTests` installs this to assert an interpolated gesture
    /// resolves the orientation/extent exactly ONCE rather than per touch step.
    /// nil (the default) in all production paths — pure no-op overhead.
    var _physicalContextResolveHook: (() -> Void)?

    public init(developerDir: String? = nil) {
        self.developerDir = developerDir ?? SPSimBridge.defaultDeveloperDir()
    }

    /// Test-only: the PHYSICAL portrait-framebuffer normalized point that a single
    /// `tap`/`touch` (and now each `multiTouch` endpoint) resolves a LOGICAL point
    /// to in the current orientation. Exposes the shared `physicalNormalized`
    /// transform so a test can assert `multiTouch` maps its endpoints identically
    /// to `tap`. Not part of the SimDriver protocol.
    func _testPhysicalNormalized(_ point: Point, udid: String) throws -> Point {
        try physicalNormalized(point, udid: udid)
    }

    public func devices() throws -> [Device] {
        let raw = try SPSimBridge.listDevices(forDeveloperDir: developerDir)
        return raw.map { d in
            Device(
                udid: d.udid,
                name: d.name,
                state: d.state,
                stateString: d.stateString,
                booted: d.isBooted,
                runtime: d.runtimeName,
                model: d.deviceTypeName
            )
        }
    }

    public func describe(_ udid: String, deep: Bool) throws -> [AXNode] {
        let raw = try SPSimBridge.accessibilityTree(
            forUDID: udid,
            deep: deep,
            developerDir: developerDir
        )
        return raw.map { Self.node(from: $0) }
    }

    public func element(at point: Point, udid: String) throws -> AXNode? {
        // Single objectAtPoint hit-test. The caller passes a LOGICAL point in the
        // CURRENT orientation (matching describe-ui frames); APT's objectAtPoint
        // (like the HID injector) consumes points in the PHYSICAL portrait
        // framebuffer space, so rotate the logical point into physical space first
        // when the device is rotated. Portrait is a pass-through. The bridge
        // returns an empty dictionary when nothing is at the point (nil + error is
        // reserved for true failures); map the empty result to no element.
        let physical = try physicalPoint(point, udid: udid)
        let raw = try SPSimBridge.elementAtPoint(
            forUDID: udid,
            x: physical.x,
            y: physical.y,
            developerDir: developerDir
        )
        guard !raw.isEmpty else { return nil }
        return Self.node(from: raw)
    }

    public func tap(_ point: Point, udid: String) throws {
        // `point` is a LOGICAL normalized 0...1 point in the CURRENT orientation;
        // the Indigo mouse injector works in the PHYSICAL portrait framebuffer, so
        // rotate it into physical-normalized space when rotated (portrait is a
        // pass-through). See OrientationMath.normalizedToPhysical.
        let physical = try physicalNormalized(point, udid: udid)
        try SPSimBridge.tapUDID(
            udid,
            normalizedX: physical.x,
            y: physical.y,
            developerDir: developerDir
        )
    }

    public func touch(_ point: Point, phase: TouchPhase, udid: String) throws {
        // Same logical->physical normalized rotation as `tap`. A single `touch`
        // resolves orientation + extent per call; the interpolated gestures
        // (`swipe`/`compositeDrag`/`longPress`) instead resolve once up front and
        // emit pre-transformed points via `touchPhysical` to avoid per-step IPC.
        let physical = try physicalNormalized(point, udid: udid)
        try touchPhysical(physical, phase: phase, udid: udid)
    }

    /// Inject an ALREADY-PHYSICAL normalized 0...1 point at `phase`. No orientation
    /// transform is applied — callers must have mapped the point already. Used by
    /// the interpolated gestures so each step skips the per-point orientation IPC +
    /// AX fetch.
    private func touchPhysical(_ physical: Point, phase: TouchPhase, udid: String) throws {
        try SPSimBridge.touchUDID(
            udid,
            phase: phase.rawValue,
            normalizedX: physical.x,
            y: physical.y,
            developerDir: developerDir
        )
    }

    public func swipe(_ a: Point, _ b: Point, duration: TimeInterval, udid: String) throws {
        // Interpolated move from a -> b in normalized 0...1 over `duration`. The
        // number of move steps scales with duration so the per-step delay stays
        // smooth (~15ms minimum step), bounded so a long duration cannot emit an
        // unbounded number of HID events.
        let stepInterval = 0.015 // seconds between interpolated moves
        let steps = max(1, min(Self.maxInterpolationSteps,
                               Int((duration / stepInterval).rounded(.up))))

        // Resolve orientation + logical extent ONCE; every interpolated point is
        // mapped with the pure helper so a rotated swipe issues no per-step IPC.
        let context = try resolvePhysicalContext(udid: udid)

        try touchPhysical(physicalNormalized(a, context: context), phase: .begin, udid: udid)
        if steps > 1 {
            let perStepDelay = duration / Double(steps)
            for i in 1...steps {
                let t = Double(i) / Double(steps)
                let p = Point(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                try touchPhysical(physicalNormalized(p, context: context), phase: .begin, udid: udid)
                if perStepDelay > 0 {
                    usleep(useconds_t(perStepDelay * 1_000_000))
                }
            }
        }
        try touchPhysical(physicalNormalized(b, context: context), phase: .end, udid: udid)
    }

    /// Composite point-to-point drag in normalized 0...1: touch-down, hold,
    /// interpolated moves over `duration`, final hold, touch-up. Used by `drag`
    /// and `slider`. Not on the SimDriver protocol — it composes `touch`.
    public func compositeDrag(
        from start: Point,
        to end: Point,
        duration: TimeInterval,
        steps: Int,
        initialHold: TimeInterval,
        finalHold: TimeInterval,
        udid: String
    ) throws {
        let stepCount = max(1, min(Self.maxInterpolationSteps, steps))

        // Resolve orientation + logical extent ONCE and reuse for every step.
        let context = try resolvePhysicalContext(udid: udid)

        try touchPhysical(physicalNormalized(start, context: context), phase: .begin, udid: udid)
        if initialHold > 0 { usleep(useconds_t(initialHold * 1_000_000)) }

        let perStepDelay = duration / Double(stepCount)
        for i in 1...stepCount {
            let t = Double(i) / Double(stepCount)
            let p = Point(x: start.x + (end.x - start.x) * t,
                          y: start.y + (end.y - start.y) * t)
            try touchPhysical(physicalNormalized(p, context: context), phase: .begin, udid: udid)
            if perStepDelay > 0 { usleep(useconds_t(perStepDelay * 1_000_000)) }
        }

        if finalHold > 0 { usleep(useconds_t(finalHold * 1_000_000)) }
        try touchPhysical(physicalNormalized(end, context: context), phase: .end, udid: udid)
    }

    /// Long-press: touch-down at `point`, hold for `hold` seconds, touch-up.
    public func longPress(_ point: Point, hold: TimeInterval, udid: String) throws {
        // Resolve orientation + logical extent ONCE; the down and up events reuse
        // the same pre-transformed physical point (no per-event IPC / AX fetch).
        let context = try resolvePhysicalContext(udid: udid)
        let physical = physicalNormalized(point, context: context)
        try touchPhysical(physical, phase: .begin, udid: udid)
        if hold > 0 { usleep(useconds_t(hold * 1_000_000)) }
        try touchPhysical(physical, phase: .end, udid: udid)
    }

    /// Upper bound on interpolated move events for a single gesture, so a long
    /// duration / large step count cannot saturate the HID transport.
    private static let maxInterpolationSteps = 1000

    // MARK: - Orientation transform (logical -> physical framebuffer)

    /// Rotate a LOGICAL normalized 0...1 point (in the current UI orientation)
    /// into the PHYSICAL portrait-framebuffer normalized space the HID injector /
    /// objectAtPoint consume. Portrait is a pass-through (no extra work, no extra
    /// AX fetch). When rotated, reads the current orientation and the logical
    /// screen frame, then applies OrientationMath.normalizedToPhysical.
    private func physicalNormalized(_ point: Point, udid: String) throws -> Point {
        let orientation = try currentOrientation(udid)
        guard orientation != .portrait else { return point }
        guard let extent = logicalExtent(udid: udid) else { return point }
        return physicalNormalized(point, orientation: orientation, extent: extent)
    }

    /// Pure (no IPC, no AX fetch) variant of `physicalNormalized(_:udid:)`: map a
    /// LOGICAL normalized point into PHYSICAL portrait-framebuffer normalized space
    /// given an already-resolved orientation and logical extent. Interpolated
    /// gestures (`swipe`/`compositeDrag`/`longPress`) resolve orientation + extent
    /// ONCE via `resolvePhysicalContext(udid:)` and reuse this for every step, so a
    /// rotated gesture issues no per-point CoreSimulator IPC or describe(deep:false)
    /// AX fetches mid-gesture. Portrait is a zero-cost pass-through.
    private func physicalNormalized(
        _ point: Point,
        orientation: UIOrientation,
        extent: (width: Double, height: Double)
    ) -> Point {
        guard orientation != .portrait else { return point }
        return OrientationMath.normalizedToPhysical(
            normalizedX: point.x,
            normalizedY: point.y,
            orientation: orientation,
            logicalWidth: extent.width,
            logicalHeight: extent.height
        )
    }

    /// Resolved orientation + logical extent for a gesture, computed once up front.
    /// `extent` is nil when no usable logical frame is available; the gesture then
    /// leaves points untransformed (matching the per-call path). Portrait short-
    /// circuits without an AX fetch so the common path stays zero-cost.
    private func resolvePhysicalContext(
        udid: String
    ) throws -> (orientation: UIOrientation, extent: (width: Double, height: Double)?) {
        _physicalContextResolveHook?()
        let orientation = try currentOrientation(udid)
        guard orientation != .portrait else { return (.portrait, nil) }
        return (orientation, logicalExtent(udid: udid))
    }

    /// Map a gesture-step point using a pre-resolved context (no IPC / AX fetch).
    /// Falls back to a pass-through when the context has no extent (rotated but no
    /// usable frame) — identical to the per-call `physicalNormalized` behavior.
    private func physicalNormalized(
        _ point: Point,
        context: (orientation: UIOrientation, extent: (width: Double, height: Double)?)
    ) -> Point {
        guard context.orientation != .portrait, let extent = context.extent else { return point }
        return physicalNormalized(point, orientation: context.orientation, extent: extent)
    }

    /// Rotate a LOGICAL point (in points, in the current UI orientation — matching
    /// describe-ui frames) into the PHYSICAL portrait-framebuffer point space that
    /// objectAtPoint consumes. Portrait is a pass-through.
    private func physicalPoint(_ point: Point, udid: String) throws -> Point {
        let orientation = try currentOrientation(udid)
        guard orientation != .portrait else { return point }
        guard let extent = logicalExtent(udid: udid) else { return point }
        let physical = OrientationMath.physicalExtent(
            logicalWidth: extent.width,
            logicalHeight: extent.height,
            orientation: orientation
        )
        return OrientationMath.translateToPhysical(
            x: point.x,
            y: point.y,
            orientation: orientation,
            portraitWidth: physical.width,
            portraitHeight: physical.height
        )
    }

    /// The current UI orientation. Failures to read it must not block input on the
    /// common portrait path, so any bridge error degrades to `.portrait`
    /// (pass-through) rather than throwing — a rotated device that cannot be read
    /// is the rare case, and the previous behavior was always-portrait anyway.
    private func currentOrientation(_ udid: String) throws -> UIOrientation {
        (try? uiOrientation(udid)) ?? .portrait
    }

    /// The logical screen frame extent (width/height in points) of the frontmost
    /// application root, used to scale normalized points to/from logical points
    /// when rotating. Returns nil when no usable frame is available (the caller
    /// then leaves the point untransformed). Only called off the portrait path.
    private func logicalExtent(udid: String) -> (width: Double, height: Double)? {
        guard let roots = try? describe(udid, deep: false) else { return nil }
        let root = roots.first { $0.type == "Application" } ?? roots.first
        guard let frame = root?.frame, frame.width > 0, frame.height > 0 else { return nil }
        return (frame.width, frame.height)
    }

    public func key(usage: Int, down: Bool, udid: String) throws {
        try SPSimBridge.sendKeyUsage(
            UInt(usage),
            down: down,
            udid: udid,
            developerDir: developerDir
        )
    }

    public func button(_ button: HardwareButton, udid: String) throws {
        try SPSimBridge.pressButton(
            button.rawValue,
            udid: udid,
            developerDir: developerDir
        )
    }

    public func screenshot(to url: URL, udid: String) throws {
        try SPSimBridge.writeFramebufferPNG(
            forUDID: udid,
            developerDir: developerDir,
            toPath: url.path
        )
    }

    public func uiOrientation(_ udid: String) throws -> UIOrientation {
        // Native READ via SimulatorKit.SimDeviceScreen.uiOrientation (UInt32
        // 1...4) — no FB frameworks, no osascript. The bridge maps the raw value
        // to the same 1...4 enum SimCore uses.
        var raw: UInt32 = 0
        try SPSimBridge.uiOrientation(
            forUDID: udid,
            developerDir: developerDir,
            rawOut: &raw,
            nameOut: nil
        )
        guard let orientation = UIOrientation(rawValue: Int(raw)) else {
            throw SimDriverError.bridge("uiOrientation returned an unexpected raw value \(raw)")
        }
        return orientation
    }

    public func setOrientation(_ name: OrientationSetName, udid: String) throws {
        // Try the native PurpleEvent SET first for the orientations it can express
        // (UIDeviceOrientation 1...4); only fall back to the osascript menu hack
        // when native is unavailable (port not vended yet / reverse-engineered wire
        // format mismatch) or the orientation is face-up/face-down. The native path
        // is headless and locale-independent, so it is strictly preferred.
        if name.isNativeExpressible {
            do {
                try SPSimBridge.setOrientationNative(
                    name.canonicalName,
                    udid: udid,
                    developerDir: developerDir
                )
                return
            } catch {
                // Fall through to osascript; the native attempt's error is non-fatal.
                FileHandle.standardError.write(
                    Data("orientation: native SET unavailable (\(error.localizedDescription)); falling back to osascript\n".utf8))
            }
        }
        try setOrientationViaOSAScript(name, udid: udid)
    }

    /// AppleScript fallback for the orientation SET. Uses Process()/osascript to
    /// click the Simulator "Device > Orientation" menu item;
    /// this is the only path that can express face-up / face-down (PurpleEvent
    /// covers only 1...4). Lives here (not in SimCore) because SimCore is pure
    /// Foundation with no Process().
    private func setOrientationViaOSAScript(_ name: OrientationSetName, udid: String) throws {
        let device = (try? deviceName(for: udid)) ?? ""
        let script = """
        on run argv
          set deviceName to item 1 of argv
          set targetOrientation to item 2 of argv
          tell application "Simulator" to activate
          delay 0.2
          tell application "System Events"
            tell process "Simulator"
              if deviceName is not "" then
                repeat with w in windows
                  if name of w contains deviceName then
                    perform action "AXRaise" of w
                    exit repeat
                  end if
                end repeat
              end if
              click menu item targetOrientation of menu 1 of menu item "Orientation" of menu 1 of menu bar item "Device" of menu bar 1
            end tell
          end tell
        end run
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-", device, name.menuItemName]
        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
        try process.run()
        input.fileHandleForWriting.write(Data(script.utf8))
        input.fileHandleForWriting.closeFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "osascript failed"
            throw SimDriverError.bridge("orientation: \(message.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    /// Resolve a device's display name (used by the osascript fallback to raise the
    /// matching Simulator window). Empty string when the UDID is not found.
    private func deviceName(for udid: String) throws -> String {
        let raw = try SPSimBridge.listDevices(forDeveloperDir: developerDir)
        return raw.first { $0.udid.caseInsensitiveCompare(udid) == .orderedSame }?.name ?? ""
    }

    public func multiTouch(_ a: Point, _ b: Point, phase: TouchPhase, udid: String) throws {
        // Both points are LOGICAL normalized 0...1 in the CURRENT orientation; the
        // multi-touch injector consumes PHYSICAL portrait-framebuffer normalized
        // coords, so rotate each endpoint exactly as `tap`/`touch` do (portrait is
        // a pass-through). Without this, a rotated pinch lands at the wrong points.
        let physicalA = try physicalNormalized(a, udid: udid)
        let physicalB = try physicalNormalized(b, udid: udid)
        try SPSimBridge.multiTouchUDID(
            udid,
            phase: phase.rawValue,
            x1: physicalA.x,
            y1: physicalA.y,
            x2: physicalB.x,
            y2: physicalB.y,
            developerDir: developerDir
        )
    }

    public func crown(delta: Double, udid: String) throws {
        try SPSimBridge.sendDigitalCrownDelta(
            delta,
            udid: udid,
            developerDir: developerDir
        )
    }

    /// Human-readable accessibility-bridge probe string (used by `sipi doctor`).
    public func accessibilityBridgeStatus() -> String {
        SPSimBridge.accessibilityBridgeStatus()
    }

    // MARK: - SimBridge node mapping

    /// Map one SimBridge serialized node dictionary into an AXNode, preserving
    /// the describe-ui contract shape SimBridge produces: AXLabel/AXValue/
    /// role_description/role/type/AXUniqueId/enabled/frame/children are always
    /// present (empty strings where SimBridge emits them, an empty array for
    /// childless nodes), and subrole only when SimBridge included it. Keeping the
    /// empty strings rather than collapsing them to nil keeps the AXNode JSON
    /// stable so skills can grep it as raw text.
    static func node(from raw: [String: Any]) -> AXNode {
        var frame: AXNode.Frame?
        if let f = raw["frame"] as? [String: Any] {
            frame = AXNode.Frame(
                x: doubleValue(f["x"]),
                y: doubleValue(f["y"]),
                width: doubleValue(f["width"]),
                height: doubleValue(f["height"])
            )
        }

        var children: [AXNode]?
        if let rawChildren = raw["children"] as? [[String: Any]] {
            children = rawChildren.map { node(from: $0) }
        }

        return AXNode(
            AXLabel: raw["AXLabel"] as? String,
            AXValue: raw["AXValue"] as? String,
            role_description: raw["role_description"] as? String,
            role: raw["role"] as? String,
            type: raw["type"] as? String,
            subrole: raw["subrole"] as? String,
            AXUniqueId: raw["AXUniqueId"] as? String,
            enabled: boolValue(raw["enabled"]),
            frame: frame,
            children: children
        )
    }

    private static func doubleValue(_ value: Any?) -> Double {
        (value as? NSNumber)?.doubleValue ?? 0
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        (value as? NSNumber)?.boolValue
    }
}
