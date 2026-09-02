// AXNodeCompact.swift
//
// A one-line-per-element rendering of the accessibility tree, for readers that
// pay per token: an agent deciding what to tap next does not need the
// pretty-printed JSON that `describe-ui` emits by default, which spends five
// lines on a frame and repeats every key name for every node.
//
// The JSON form stays the contract — verify grep, `--expect`, and the harness
// all read it. This form is opt-in (`describe-ui --format compact`) and carries
// the same facts in a shape that is still grep-friendly: one element per line,
// indented by depth, with the fields a driver actually acts on.
//
//   Button "Sign In" id="auth.sign-in" frame=(24,88,168,44) hit=(108,110)
//   TextField id="email" value="" frame=(16,200,343,44) hit=(187,222)
//   Switch "Notifications" value="1" frame=(...) hit=(...) disabled
//   Cell "Row 12" frame=(0,912,393,44) offscreen
//
// Rules, so the output is predictable enough to grep:
//   - The first token is `type` when the node reports one, else `role` with its
//     `AX` prefix removed, else `Element`.
//   - `"label"` follows when the node has a label. `id="…"` is emitted whenever
//     present, even when equal to the label: a reader looking for a selector
//     must not have to guess whether an id exists. `value="…"` is emitted when
//     non-empty, and also when empty on a text-entry element, where "empty" is
//     the fact; containers report an empty value for nothing and stay silent.
//   - Strings are quoted with `"`, `\`, and newlines escaped as `\"`, `\\`, `\n`.
//   - Coordinates are rounded to whole points. `frame=(x,y,w,h)`; `hit=(x,y)`.
//   - `disabled` appears only when `enabled` is reported false; `offscreen` only
//     when `onscreen` is reported false — the defaults (enabled, on screen) are
//     the common case and stay silent.
//   - `role_description` and `subrole` are dropped: they restate `type`.

import Foundation

public enum AXNodeCompact {
    /// The compact rendering of a node array, one element per line, with a
    /// trailing newline after the last line. An empty tree renders as "".
    public static func string(for nodes: [AXNode]) -> String {
        var lines: [String] = []
        for node in nodes {
            append(node, depth: 0, into: &lines)
        }
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }

    /// One node's line, without its children.
    public static func line(for node: AXNode) -> String {
        var parts: [String] = [kind(of: node)]
        if let label = node.AXLabel, !label.isEmpty {
            parts.append(quoted(label))
        }
        if let id = node.AXUniqueId, !id.isEmpty {
            parts.append("id=" + quoted(id))
        }
        // Containers report an empty AXValue for nothing; on a text field an empty
        // value is the fact "this field is empty". Emit empty only where it means
        // something.
        if let value = node.AXValue, !value.isEmpty || node.isTextEntry {
            parts.append("value=" + quoted(value))
        }
        if let f = node.frame {
            parts.append("frame=(\(whole(f.x)),\(whole(f.y)),\(whole(f.width)),\(whole(f.height)))")
        }
        if let p = node.hitPoint {
            parts.append("hit=(\(whole(p.x)),\(whole(p.y)))")
        }
        if node.enabled == false {
            parts.append("disabled")
        }
        if node.onscreen == false {
            parts.append("offscreen")
        }
        return parts.joined(separator: " ")
    }

    private static func append(_ node: AXNode, depth: Int, into lines: inout [String]) {
        lines.append(String(repeating: "  ", count: depth) + line(for: node))
        for child in node.children ?? [] {
            append(child, depth: depth + 1, into: &lines)
        }
    }

    private static func kind(of node: AXNode) -> String {
        if let type = node.type, !type.isEmpty { return type }
        if let role = node.role, !role.isEmpty {
            return role.hasPrefix("AX") ? String(role.dropFirst(2)) : role
        }
        return "Element"
    }

    /// Round half away from zero so a 0.5 boundary lands on the same side the
    /// reader would expect; then drop the fraction. `-0` renders as `0`.
    private static func whole(_ value: Double) -> String {
        let rounded = value.rounded()
        if rounded == 0 { return "0" }
        return String(Int(rounded))
    }

    private static func quoted(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }
}
