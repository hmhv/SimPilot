// SemanticVersion.swift
//
// Minimal semver parsing + comparison for the `sipi update` release check.
// Compares the running `sipiVersion` against the latest GitHub Release tag to
// decide whether an update is available. Tolerant of a leading "v" (release tags
// are usually "v1.2.3") and of a missing patch/minor component; pre-release and
// build-metadata suffixes are ignored for the comparison.
//
// Pure Foundation, no network — kept here so the comparison stays unit-testable.

import Foundation

/// A dot-separated numeric version (major.minor.patch), comparable by component.
public struct SemanticVersion: Comparable, Equatable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parse a version string such as "1.2.3", "v1.2.3", "1.2", or "v2".
    /// Missing components default to 0. A leading "v"/"V" and any
    /// pre-release ("-rc.1") or build ("+meta") suffix are ignored. Returns nil
    /// if no leading numeric component can be parsed.
    public init?(_ raw: String) {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmed.first, first == "v" || first == "V" {
            trimmed.removeFirst()
        }
        // Drop any pre-release / build metadata suffix.
        if let cut = trimmed.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            trimmed = String(trimmed[..<cut])
        }
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard let firstPart = parts.first, let major = Int(firstPart) else { return nil }
        self.major = major
        self.minor = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
        self.patch = parts.count > 2 ? (Int(parts[2]) ?? 0) : 0
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}
