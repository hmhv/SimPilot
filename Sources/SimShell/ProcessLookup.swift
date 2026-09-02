// ProcessLookup.swift
//
// Find the pid of an app running on a simulator, by bundle identifier.
//
// `devicectl device info processes` reports only pids on a simulator (no
// executable, no bundle id), so it cannot answer "which pid is my app". The
// guest's launchd can: `simctl spawn <udid> launchctl list` prints one line per
// job, and a foreground app's job is labelled
// `UIKitApplication:<bundle-id>[<hash>][rb-legacy]`. That label is what the
// memory-warning path keys on.

import Foundation

public enum LaunchctlList {
    /// Parse `launchctl list` output and return the pid of the UIKit
    /// application job for `bundleID`, or nil when no such job is running.
    ///
    /// Each line is `<pid>\t<last exit status>\t<label>`; a job with no live
    /// process shows `-` in the pid column and is skipped. The label match is
    /// exact on the bundle id: `UIKitApplication:com.example.app[` must not match
    /// `com.example.app.extension`.
    public static func processIdentifier(in listing: String, bundleID: String) -> Int32? {
        let prefix = "UIKitApplication:" + bundleID + "["
        for rawLine in listing.split(separator: "\n", omittingEmptySubsequences: true) {
            let columns = rawLine.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard columns.count == 3 else { continue }
            let label = columns[2].trimmingCharacters(in: .whitespaces)
            guard label.hasPrefix(prefix), let pid = Int32(columns[0].trimmingCharacters(in: .whitespaces)) else {
                continue
            }
            return pid
        }
        return nil
    }
}

extension SimShell {
    /// The pid of `bundleID`'s running UIKit process on `udid`, or nil when the
    /// app is not running. Reads the guest launchd job table through
    /// `simctl spawn <udid> launchctl list`.
    public static func processIdentifier(udid: String, bundleID: String) throws -> Int32? {
        try requireBooted(udid)
        let listing = try spawnChecked(udid: udid, ["launchctl", "list"])
        return LaunchctlList.processIdentifier(in: listing, bundleID: bundleID)
    }
}
