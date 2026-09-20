// DisplayResolver.swift
//
// Reads the device's screens through devicectl and caches only the answer that
// cannot change.
//
// A device with one built-in screen can only ever answer one way, so that
// reading is kept for the life of the process — the harness screenshots every
// step from one process, and this keeps the cost at one subprocess per run
// rather than one per capture.
//
// A foldable's answer changes the moment someone folds it in Device Hub, and
// nothing notifies anyone that it did. So a multi-screen device is re-read every
// time: ~0.07s, against a black PNG for getting it wrong.

import Foundation
import SimCore
import SimShell

public enum DisplayResolver {
    /// Screens for devices that have exactly one — keyed by UDID, never
    /// invalidated, because a device cannot grow a screen.
    private nonisolated(unsafe) static var singleScreenCache: [String: DeviceDisplay] = [:]
    private static let cacheLock = NSLock()

    /// The device's built-in screens, or an empty array when devicectl cannot
    /// answer (Xcode 26 and earlier, a device that is not booted, a coredevice
    /// daemon still starting). An empty result is never cached: it says nothing
    /// about the device, and caching it would pin the process to the
    /// single-screen fallback over one bad moment.
    public static func displays(udid: String) -> [DeviceDisplay] {
        cacheLock.lock()
        let cached = singleScreenCache[udid]
        cacheLock.unlock()
        if let cached { return [cached] }

        // No `isSimulatorCapable()` probe first. It would cost a second
        // subprocess on every capture — sipi is a one-shot CLI, so nothing
        // caches across calls — to learn what the read itself reports by
        // failing. A toolchain whose devicectl cannot target simulators simply
        // returns nothing here and the caller falls back.
        guard let displays = try? DeviceCtl.displays(udid: udid), !displays.isEmpty else {
            return []
        }

        if displays.count == 1 {
            cacheLock.lock()
            singleScreenCache[udid] = displays[0]
            cacheLock.unlock()
        }
        return displays
    }

    /// The screen `selector` names, or nil when the screens cannot be read at
    /// all — in which case the caller falls back to SimBridge's own
    /// single-screen reading rather than failing.
    ///
    /// A selector that names a screen this device does not have still throws:
    /// that is a caller mistake, not a missing capability, and silently
    /// capturing a different screen is the failure `--display` exists to stop.
    public static func resolve(
        _ selector: DisplaySelection.Selector,
        udid: String
    ) throws -> DeviceDisplay? {
        let displays = displays(udid: udid)
        guard !displays.isEmpty else { return nil }
        return try DisplaySelection.resolve(selector, in: displays)
    }

    /// Test seam: forget what was cached, so a test can change what devicectl
    /// would answer.
    public static func resetCache() {
        cacheLock.lock()
        singleScreenCache.removeAll()
        cacheLock.unlock()
    }
}
