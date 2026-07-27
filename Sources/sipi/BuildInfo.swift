// BuildInfo.swift
//
// Where the running `sipi` came from, and whether it still matches the checkout
// it is being run inside.
//
// `sipi version` prints the semver only, so a source fix that does not bump
// VERSION leaves a stale install indistinguishable from a current one: the
// binary answers "1.1.0", the checkout says "1.1.0", and the behavior everyone
// is looking at is the old one. `doctor` therefore reports the binary path and
// install time, and — only when the process is running inside a SimPilot
// checkout, where the comparison is meaningful — warns when the checkout has
// moved past the binary.
//
// Advisory only: this never changes `doctor`'s exit code. Running a released
// binary from inside a checkout is legitimate, and a probe that guesses about
// provenance must not be able to block a working setup.

import Foundation

struct BuildInfo {
    /// Absolute path of the running executable, when it can be resolved.
    var binaryPath: String?
    /// Last-modified time of the running executable — when this build landed at
    /// `binaryPath`. Build time for a `swift build` output, copy time for an
    /// installed one; both answer "how old is what I am running".
    var binaryModified: Date?
    /// The enclosing SimPilot checkout, when there is one on the CWD's path.
    var checkout: Checkout?

    struct Checkout {
        /// Absolute path of the checkout root.
        var root: String
        /// Short HEAD SHA.
        var head: String
        /// HEAD commit date.
        var headDate: Date
        /// Whether tracked files under `Sources/` have uncommitted modifications.
        var sourcesDirty: Bool
    }

    /// True when the checkout's HEAD commit is newer than the running binary —
    /// i.e. source landed after this binary was built/installed, so the behavior
    /// under test is not the behavior in the checkout.
    var isStale: Bool {
        guard let binaryModified, let checkout else { return false }
        return checkout.headDate > binaryModified
    }

    static func probe(
        cwd: String = FileManager.default.currentDirectoryPath,
        binaryPath: String? = Bundle.main.executablePath
    ) -> BuildInfo {
        var info = BuildInfo(binaryPath: binaryPath)
        if let binaryPath,
           let attributes = try? FileManager.default.attributesOfItem(atPath: binaryPath) {
            info.binaryModified = attributes[.modificationDate] as? Date
        }
        info.checkout = simPilotCheckout(startingAt: cwd).flatMap(checkoutState(root:))
        return info
    }

    /// Human-readable one-liner for `doctor`'s notes: what is running and from
    /// where. Nil only when the executable path cannot be resolved at all.
    var summaryNote: String? {
        guard let binaryPath else { return nil }
        var note = "binary: \(binaryPath)"
        if let binaryModified {
            note += " (modified \(BuildInfo.iso8601(binaryModified)))"
        }
        return note
    }

    /// The staleness warning, when the surrounding checkout has outrun the
    /// binary. Nil when there is no checkout, no timestamps, or nothing to warn
    /// about.
    var stalenessWarning: String? {
        guard let checkout else { return nil }
        if isStale {
            var warning = "warning: this binary predates the SimPilot checkout at \(checkout.root)"
            warning += " (HEAD \(checkout.head), committed \(BuildInfo.iso8601(checkout.headDate)))."
            warning += " Rebuild and reinstall before trusting a source change:"
            warning += " swift build -c release && cp .build/release/sipi \"$(command -v sipi)\""
            return warning
        }
        if checkout.sourcesDirty {
            return "note: the SimPilot checkout at \(checkout.root) has uncommitted changes under"
                + " Sources/ — rebuild if they are meant to be under test."
        }
        return nil
    }

    static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    // MARK: - Checkout resolution

    /// Walk up from `start` looking for a SimPilot checkout: a git working tree
    /// whose package is this one. All three markers are required so an unrelated
    /// Swift package (or an unrelated repo containing one) is never mistaken for
    /// SimPilot — the same conservatism `preflight.md`'s resolver uses.
    private static func simPilotCheckout(startingAt start: String) -> String? {
        let fileManager = FileManager.default
        var directory = URL(fileURLWithPath: start).standardizedFileURL
        while true {
            let path = directory.path
            let hasGit = fileManager.fileExists(atPath: path + "/.git")
            let hasPackage = fileManager.fileExists(atPath: path + "/Package.swift")
            let hasCLISources = fileManager.fileExists(atPath: path + "/Sources/sipi")
            if hasGit && hasPackage && hasCLISources { return path }
            let parent = directory.deletingLastPathComponent().standardizedFileURL
            if parent.path == path { return nil }
            directory = parent
        }
    }

    /// HEAD identity + `Sources/` dirtiness for `root`, via read-only git calls.
    /// Nil when git is unavailable or the repo has no commits yet.
    private static func checkoutState(root: String) -> Checkout? {
        guard let headLine = git(["-C", root, "log", "-1", "--format=%h %cI"]),
              let separator = headLine.firstIndex(of: " ") else { return nil }
        let head = String(headLine[headLine.startIndex..<separator])
        let dateText = String(headLine[headLine.index(after: separator)...])
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let headDate = formatter.date(from: dateText) else { return nil }
        let status = git(["-C", root, "status", "--porcelain", "--", "Sources"])
        return Checkout(
            root: root,
            head: head,
            headDate: headDate,
            sourcesDirty: !(status ?? "").isEmpty
        )
    }

    /// Run `git` and return trimmed stdout, or nil on any failure. Read-only
    /// calls only; a missing/unhappy git degrades to "no checkout information".
    private static func git(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
