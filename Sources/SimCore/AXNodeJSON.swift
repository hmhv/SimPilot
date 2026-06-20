// AXNodeJSON.swift
//
// describe-ui JSON contract encoder. The output MUST be a top-level array,
// pretty-printed in the spaced-colon `"key" : "value"` style that
// JSONSerialization(.prettyPrinted) produces, because skills grep it as raw
// text. Only present fields are emitted, in the same shape SimBridge already
// serializes.

import Foundation

public enum AXNodeJSON {
    /// Convert one node into a JSONSerialization-compatible dictionary,
    /// preserving the describe-ui field names and nesting. Only non-nil fields
    /// are included.
    public static func dictionary(for node: AXNode) -> [String: Any] {
        var dict: [String: Any] = [:]
        if let v = node.AXLabel { dict["AXLabel"] = v }
        if let v = node.AXValue { dict["AXValue"] = v }
        if let v = node.role_description { dict["role_description"] = v }
        if let v = node.role { dict["role"] = v }
        if let v = node.type { dict["type"] = v }
        if let v = node.subrole { dict["subrole"] = v }
        if let v = node.AXUniqueId { dict["AXUniqueId"] = v }
        if let v = node.enabled { dict["enabled"] = v }
        if let f = node.frame {
            dict["frame"] = [
                "x": f.x, "y": f.y, "width": f.width, "height": f.height
            ]
        }
        if let children = node.children {
            dict["children"] = children.map { dictionary(for: $0) }
        }
        return dict
    }

    /// Pretty-printed describe-ui JSON for a node array. Top-level array, spaced
    /// colons — the verify-form contract skills grep against.
    public static func data(for nodes: [AXNode]) throws -> Data {
        let array = nodes.map { dictionary(for: $0) }
        return try JSONSerialization.data(withJSONObject: array, options: [.prettyPrinted])
    }

    /// Pretty-printed describe-ui JSON string for a node array.
    public static func string(for nodes: [AXNode]) throws -> String {
        let data = try data(for: nodes)
        return String(decoding: data, as: UTF8.self)
    }
}

extension AXNode {
    /// Pretty-printed describe-ui JSON for a tree of nodes. The CLI calls this to
    /// emit the `describe-ui` contract output (top-level array, spaced-colon
    /// `"key" : "value"` style).
    public static func encodeTreeJSON(_ nodes: [AXNode]) throws -> String {
        try AXNodeJSON.string(for: nodes)
    }
}
