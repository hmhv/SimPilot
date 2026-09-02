// RunRetention.swift
//
// Which run directories `keep-runs` removes. Pure: the harness lists
// `<workspace>/runs`, hands the names here, and deletes what comes back.
//
// Only directories the harness itself wrote are candidates: the default run-dir
// shape is `yyyy-MM-dd_HHmmss_<device>_<commit>`, AND the directory must hold a
// `run.json` with a `finished` timestamp. The name alone is not enough — a
// person can copy a run aside under a stamped name — and `finished` is what
// separates a completed run from one another `sipi` process is still writing
// in the same workspace. Sorting by name is sorting by time, which is why the
// stamp leads the name.

import Foundation

public enum RunRetention {
    /// Matches the leading timestamp of a harness-named run directory.
    static let stampPattern = try! NSRegularExpression(pattern: #"^\d{4}-\d{2}-\d{2}_\d{6}_"#)

    /// The run-directory names to delete so that at most `keep` harness-named
    /// runs remain, oldest first. `keep` of zero or less disables pruning
    /// (returns []) rather than deleting everything: a misread config must not
    /// wipe a runs folder.
    public static func directoriesToPrune(names: [String], keep: Int) -> [String] {
        guard keep > 0 else { return [] }
        let candidates = names.filter { isHarnessRunName($0) }.sorted(by: >)
        guard candidates.count > keep else { return [] }
        return Array(candidates.dropFirst(keep)).sorted()
    }

    public static func isHarnessRunName(_ name: String) -> Bool {
        stampPattern.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
    }

    /// Whether `path` is a run the harness finished writing: it holds a
    /// `run.json` whose `finished` is a non-empty string. A directory without
    /// one is either not a run at all or a run still in progress (the harness
    /// writes `run.json` with no `finished` at start and fills it in at the end),
    /// and neither may be deleted.
    public static func isCompletedRun(at path: String) -> Bool {
        guard let data = FileManager.default.contents(atPath: path + "/run.json"),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let finished = object["finished"] as? String else { return false }
        return !finished.isEmpty
    }
}
