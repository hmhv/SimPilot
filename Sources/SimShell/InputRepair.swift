// InputRepair.swift
//
// Detects and undoes Device Hub cutting a simulator off from legacy input.
//
// Xcode 27's Device Hub drives touches and keys through CoreDevice's own HID
// daemon, and while it does the guest raises the notify state
// `com.apple.coredevice.dtuhidd.active` to 1. With it raised, the legacy HID path
// sipi injects through can stop being delivered: taps report ok and nothing
// happens. Clearing the state and restarting backboardd reconnects it. The
// restart takes SpringBoard down with it, so every running app is closed — which
// is why this is a command someone runs, never something sipi does on its own.
//
// Recipe from serve-sim (`repair-input`).

import Foundation

extension SimShell {
    static let deviceHubInputState = "com.apple.coredevice.dtuhidd.active"

    /// Whether Device Hub has taken this device's input over (see the file
    /// header). Throws when the guest cannot be asked — a device that is not
    /// booted.
    public static func isInputShadowedByDeviceHub(udid: String) throws -> Bool {
        // notifyutil -g prints "<name> <value>".
        let output = try spawnChecked(udid: udid, ["notifyutil", "-g", deviceHubInputState])
        return output.trimmingCharacters(in: .whitespacesAndNewlines) == "\(deviceHubInputState) 1"
    }

    /// Clear Device Hub's hold on input and restart backboardd. Returns false,
    /// changing nothing, when input was not shadowed in the first place.
    @discardableResult
    public static func repairDeviceHubInput(udid: String) throws -> Bool {
        guard try isInputShadowedByDeviceHub(udid: udid) else { return false }
        _ = try spawnChecked(udid: udid, ["notifyutil", "-s", deviceHubInputState, "0"])
        _ = try spawnChecked(udid: udid, ["launchctl", "kickstart", "-k", "system/com.apple.backboardd"])
        return true
    }
}
