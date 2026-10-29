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
import SimShell

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
        // The grid pass sweeps points in the tree's LOGICAL space but hands them
        // to a hit-test that reads PHYSICAL portrait coordinates. Those agree
        // only in portrait; rotated, the probe points land somewhere else
        // entirely, so the points it recorded are not where those elements are
        // and must not be presented as hit points. (Grid discovery on a rotated
        // device is unreliable for the same reason — a pre-existing limit this
        // only declines to make worse.)
        // nil means the orientation could not be READ, which is not the same as
        // portrait — and the difference decides whether the root's frame may be
        // rewritten below.
        let orientation = try? uiOrientation(udid)
        let portrait = (orientation ?? .portrait) == .portrait
        let nodes = raw.map { Self.node(from: $0, trustProbeHitPoints: portrait) }
        // Every node leaves the driver with a hitPoint it is safe to touch and an
        // honest onscreen flag; without this a caller has only frames, which are
        // not tap targets (see HitPoints.swift).
        //
        // Correct the ROOT's frame rather than only clipping against the right
        // rectangle, because the root's frame is what every caller reads as "the
        // screen": HitPoints clips with it, `describe-point` and `--pixel`
        // convert through it, and pixel-unit coordinates are sized by it.
        // Fixing one consumer and not the others would leave two disagreeing
        // ideas of how big the screen is, which is worse than one wrong one.
        //
        // They are the same rectangle on every device with one screen. They
        // differ on an iPhone Duo's inner screen, where the root reports the
        // unrotated panel (669x951) while its own children are laid out in the
        // rotated space around it — a button spanning to x=844 inside a root
        // claiming to be 669 wide, which then read as off-screen and had its tap
        // point clipped to the wrong place.
        //
        // Only when the orientation is actually KNOWN. Assuming portrait and
        // rewriting anyway would overwrite a correct landscape root (874x402 on
        // an iPhone 17) with the unswapped panel size, producing on a perfectly
        // ordinary device the exact contradiction this exists to remove. The
        // tree came from a separate read that a failed orientation read says
        // nothing about, so leaving it alone is the honest answer.
        let corrected = HitPoints.withScreenFrame(
            nodes,
            screen: orientation.flatMap { screenFrame(udid: udid, orientation: $0) })
        return HitPoints.annotate(corrected, screen: HitPoints.screenFrame(of: corrected))
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
        var node = Self.node(from: raw)
        // `point` is already in the logical space describe-ui frames use, and it
        // just reached this element, so it is by construction a point that hits
        // it — better ground truth than anything the element's frame can offer,
        // which for a remote view is not even in screen space.
        node.hitPoint = AXNode.Frame.Point(x: point.x, y: point.y)
        node.onscreen = true
        return node
    }

    public func setValue(_ value: String, at point: Point, udid: String) throws {
        // Same coordinate contract as `element(at:)`: the caller passes a LOGICAL
        // point in the current orientation and the bridge's hit-test consumes
        // PHYSICAL portrait coordinates, so rotate first.
        let physical = try physicalPoint(point, udid: udid)
        try SPSimBridge.setAccessibilityValue(
            value,
            at: CGPoint(x: physical.x, y: physical.y),
            forUDID: udid,
            developerDir: developerDir
        )
    }

    public func tap(_ point: Point, udid: String) throws {
        // `point` is a LOGICAL normalized 0...1 point in the CURRENT orientation;
        // the Indigo mouse injector works in the PHYSICAL portrait framebuffer, so
        // rotate it into physical-normalized space when rotated (portrait is a
        // pass-through). See OrientationMath.normalizedToPhysical.
        let physical = try physicalNormalized(point, udid: udid)
        try routeTouches(udid: udid)
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
        try routeTouches(udid: udid)
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
        try routeTouches(udid: udid)

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
        try routeTouches(udid: udid)

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
        try routeTouches(udid: udid)
        let physical = physicalNormalized(point, context: context)
        try touchPhysical(physical, phase: .begin, udid: udid)
        if hold > 0 { usleep(useconds_t(hold * 1_000_000)) }
        try touchPhysical(physical, phase: .end, udid: udid)
    }

    /// Upper bound on interpolated move events for a single gesture, so a long
    /// duration / large step count cannot saturate the HID transport.
    private static let maxInterpolationSteps = 1000

    /// Point the touches that follow at the lit screen's own digitizer, on a
    /// device that has one per screen (iPhone Duo); a no-op anywhere else, and
    /// without the devicectl read there. Called once per gesture, before its
    /// first touch.
    ///
    /// Measured on Xcode 27.2 / iOS 27.2: the shared slot every other device
    /// uses reaches a Duo's inner screen and never its cover. With no screen lit
    /// (asleep), or the screens unreadable, touches stay on the shared slot.
    private func routeTouches(udid: String) throws {
        guard SPSimBridge.hasSeparateTouchscreens(forUDID: udid, developerDir: developerDir) else { return }
        let lit = (try? DisplayResolver.resolve(.active, udid: udid)) ?? nil
        try SPSimBridge.setTouchScreenID(lit?.screenID ?? 0, udid: udid, developerDir: developerDir)
    }

    // MARK: - Orientation transform (logical -> physical framebuffer)

    /// Rotate a LOGICAL normalized 0...1 point (in the current UI orientation)
    /// into the PHYSICAL portrait-framebuffer normalized space the HID injector /
    /// objectAtPoint consume. Portrait is a pass-through (no extra work, no extra
    /// AX fetch). When rotated, reads the current orientation and the logical
    /// screen frame, then applies OrientationMath.normalizedToPhysical.
    private func physicalNormalized(_ point: Point, udid: String) throws -> Point {
        let orientation = try currentOrientation(udid)
        guard orientation != .portrait else { return point }
        guard let extent = logicalExtent(udid: udid, orientation: orientation) else { return point }
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
        return (orientation, logicalExtent(udid: udid, orientation: orientation))
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
        guard let extent = logicalExtent(udid: udid, orientation: orientation) else { return point }
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
    /// The screen as a frame at the origin, or nil when the screens cannot be
    /// read. Deliberately does NOT fall back to the accessibility root the way
    /// `logicalExtent` does: `describe` already has the root to hand and falls
    /// back to it itself, and going through the fallback here would re-enter
    /// `describe`.
    private func screenFrame(udid: String, orientation: UIOrientation) -> AXNode.Frame? {
        guard let extent = screenExtent(udid: udid, orientation: orientation) else { return nil }
        return AXNode.Frame(x: 0, y: 0, width: extent.width, height: extent.height)
    }

    /// The lit screen's point size, swapped when the UI is on its side.
    private func screenExtent(
        udid: String,
        orientation: UIOrientation
    ) -> (width: Double, height: Double)? {
        guard let screen = (try? DisplayResolver.resolve(.active, udid: udid)) ?? nil,
              screen.pointWidth > 0, screen.pointHeight > 0
        else { return nil }
        let extent = screen.logicalExtent(in: orientation)
        return (Double(extent.width), Double(extent.height))
    }

    /// The size of the space `describe-ui` frames live in, in points.
    ///
    /// Taken from the SCREEN — a fact about the device — rotated by the current
    /// orientation, rather than from the accessibility root's frame, which is
    /// only a proxy for it.
    ///
    /// The proxy is right on every device with one screen: measured on iPhone 17
    /// / iOS 27.0, a 402x874 panel reports a 402x874 root in portrait and an
    /// 874x402 root in landscape-left — exactly what swapping the screen size
    /// gives. It is wrong on an iPhone Duo's INNER screen, which sits in
    /// landscape-left and reports a 669x951 root (the unrotated panel) while its
    /// elements are laid out in the 951x669 space around it. Every gesture is
    /// rotated by these two numbers, so swapped they put each touch somewhere
    /// the element is not: on that screen no tap landed at all.
    ///
    /// Falls back to the root's frame when the screens cannot be read.
    private func logicalExtent(
        udid: String,
        orientation: UIOrientation
    ) -> (width: Double, height: Double)? {
        if let extent = screenExtent(udid: udid, orientation: orientation) { return extent }
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
        // swipe_home is a touch gesture, not a button event.
        if button == .swipeHome { try routeTouches(udid: udid) }
        try SPSimBridge.pressButton(
            button.rawValue,
            udid: udid,
            developerDir: developerDir
        )
    }

    /// Capture what is on screen, whatever that turns out to be.
    ///
    /// Deliberately NOT `screenshot(to:udid:display: .active)`. Naming a screen
    /// is strict — asking for one the device cannot give you is an error — but a
    /// caller who named nothing asked for a picture, and refusing to produce one
    /// because the screens could not be told apart would be a worse answer than
    /// the bridge's own single-screen reading.
    public func screenshot(to url: URL, udid: String) throws {
        let resolved = try? DisplayResolver.resolve(.active, udid: udid)
        try capture(to: url, udid: udid, display: resolved ?? nil)
    }

    /// Captures the screen `display` names, resolved to the pixel size the
    /// bridge matches surfaces by.
    ///
    /// Passing the size down rather than letting the bridge work it out is what
    /// makes a foldable capturable at all: the bridge sees several live
    /// framebuffers and, on iPhone Duo, both built-in ones are live whichever
    /// way the device is folded — the dark one solid black. Only the resolved
    /// screen tells them apart.
    ///
    /// When the screens cannot be read (a device still coming up) the bridge
    /// falls back to its own single-screen reading, which is right for every
    /// device that has one screen.
    public func screenshot(to url: URL, udid: String, display: DisplaySelection.Selector) throws {
        try capture(to: url, udid: udid, display: try DisplayResolver.resolve(display, udid: udid))
    }

    /// nil means "the bridge decides": its own reading is right for every device
    /// with one screen, and is all a toolchain that cannot read the screen list
    /// has to offer.
    private func capture(to url: URL, udid: String, display: DeviceDisplay?) throws {
        try SPSimBridge.writeFramebufferPNG(
            forUDID: udid,
            developerDir: developerDir,
            displayPixelWidth: display?.pixelWidth ?? 0,
            displayPixelHeight: display?.pixelHeight ?? 0,
            toPath: url.path
        )
        // The framebuffer comes out the way the panel is mounted; turn it the
        // way the screen is being held (see DeviceDisplay.uprightQuarterTurns).
        if let turns = display?.uprightQuarterTurns,
           let original = try? Data(contentsOf: url),
           let upright = PNGRotate.rotated(original, quarterTurnsClockwise: turns) {
            try upright.write(to: url, options: .atomic)
        }
    }

    public func uiOrientation(_ udid: String) throws -> UIOrientation {
        // Native READ via SimulatorKit.SimDeviceScreen.uiOrientation (UInt32
        // 1...4) — no FB frameworks, no osascript. The bridge maps the raw value
        // to the same 1...4 enum SimCore uses.
        //
        // The screen has to be named. Every gesture this driver sends is rotated
        // by this value, and on iPhone Duo the bridge's default — screen 1 — is
        // the COVER: while the device is open that reports the orientation of a
        // screen that is switched off, and every tap lands somewhere else. 0
        // keeps the screen-1 reading for when the screens cannot be read.
        let active = (try? DisplayResolver.resolve(.active, udid: udid)) ?? nil
        var raw: UInt32 = 0
        try SPSimBridge.uiOrientation(
            forUDID: udid,
            developerDir: developerDir,
            screenID: active.map { $0.screenID } ?? 0,
            rawOut: &raw,
            nameOut: nil
        )
        guard let orientation = UIOrientation(rawValue: Int(raw)) else {
            throw SimDriverError.bridge("uiOrientation returned an unexpected raw value \(raw)")
        }
        return orientation
    }

    public func setOrientation(_ name: OrientationSetName, udid: String) throws {
        // Native PurpleEvent SET first: headless, in-process, but only
        // UIDeviceOrientation 1...4. devicectl reaches face-up / face-down too, at
        // the cost of a process spawn.
        if name.isNativeExpressible {
            do {
                try SPSimBridge.setOrientationNative(
                    name.canonicalName,
                    udid: udid,
                    developerDir: developerDir
                )
                return
            } catch {
                warn("orientation: native SET unavailable (\(error.localizedDescription)); trying devicectl")
            }
        }
        try DeviceCtl.setOrientation(udid: udid, name: name.deviceCtlName)
    }

    private func warn(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    public func multiTouch(_ a: Point, _ b: Point, phase: TouchPhase, udid: String) throws {
        // Both points are LOGICAL normalized 0...1 in the CURRENT orientation; the
        // multi-touch injector consumes PHYSICAL portrait-framebuffer normalized
        // coords, so rotate each endpoint exactly as `tap`/`touch` do (portrait is
        // a pass-through). Without this, a rotated pinch lands at the wrong points.
        let physicalA = try physicalNormalized(a, udid: udid)
        let physicalB = try physicalNormalized(b, udid: udid)
        try routeTouches(udid: udid)
        try sendMultiTouch(physicalA, physicalB, phase: phase, udid: udid)
    }

    public func multiTouchSequence(_ frames: [MultiTouchFrame], frameDelay: TimeInterval, udid: String) throws {
        guard !frames.isEmpty else { return }
        // Resolve orientation + logical extent ONCE, exactly as the interpolated
        // single-finger gestures do. Doing it per frame would cost two
        // CoreSimulator round trips and two AX fetches per frame on a rotated
        // device — enough delay between moves that the guest no longer reads the
        // sequence as one continuous gesture.
        let context = try resolvePhysicalContext(udid: udid)
        try routeTouches(udid: udid)
        let lastIndex = frames.count - 1
        for (index, frame) in frames.enumerated() {
            try sendMultiTouch(
                physicalNormalized(frame.a, context: context),
                physicalNormalized(frame.b, context: context),
                phase: frame.phase,
                udid: udid
            )
            // Pace the interpolated moves only. The opening touch-down and the
            // closing lift follow immediately, so the recognizer never sees a
            // stalled hold at either end.
            if index > 0, index < lastIndex, frameDelay > 0 {
                usleep(useconds_t(min(max(frameDelay, 0), 5) * 1_000_000))
            }
        }
    }

    private func sendMultiTouch(_ a: Point, _ b: Point, phase: TouchPhase, udid: String) throws {
        try SPSimBridge.multiTouchUDID(
            udid,
            phase: phase.rawValue,
            x1: a.x,
            y1: a.y,
            x2: b.x,
            y2: b.y,
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
    static func node(from raw: [String: Any], trustProbeHitPoints: Bool = true) -> AXNode {
        var frame: AXNode.Frame?
        if let f = raw["frame"] as? [String: Any] {
            frame = AXNode.Frame(
                x: doubleValue(f["x"]),
                y: doubleValue(f["y"]),
                width: doubleValue(f["width"]),
                height: doubleValue(f["height"])
            )
        }

        // Present only for elements the grid pass reached by hit-testing, where
        // the probe point is the one trustworthy screen coordinate for the
        // element (see SPRecordProbeHit in SimBridge.m).
        var hitPoint: AXNode.Frame.Point?
        if trustProbeHitPoints, let p = raw["hitPoint"] as? [String: Any] {
            hitPoint = AXNode.Frame.Point(x: doubleValue(p["x"]), y: doubleValue(p["y"]))
        }

        var children: [AXNode]?
        if let rawChildren = raw["children"] as? [[String: Any]] {
            children = rawChildren.map { node(from: $0, trustProbeHitPoints: trustProbeHitPoints) }
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
            hitPoint: hitPoint,
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
