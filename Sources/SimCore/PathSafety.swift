// PathSafety.swift
//
// Guards against path traversal from model/JSON-authored identifiers and names.
// A test `id` or a capture `check` becomes a directory/file name under the run
// output; an unchecked `../` would let a spec write outside the workspace.

import Foundation

public enum PathSafety {
    /// True iff `component` is a safe single path component: non-empty, not `.`
    /// or `..`, and free of path separators and NUL bytes.
    public static func isSafeComponent(_ component: String) -> Bool {
        !component.isEmpty
            && component != "."
            && component != ".."
            && !component.contains("/")
            && !component.contains("\u{0}")
    }
}
