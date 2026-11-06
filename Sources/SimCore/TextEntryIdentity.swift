import Foundation

/// A text field's identity before writing. Its value cannot identify it because
/// writing changes that value, and its frame can move when the keyboard opens.
public struct TextEntryIdentity: Equatable, Sendable {
    private let identifier: String?
    private let label: String?
    private let type: String?

    public init?(element: AXNode, in roots: [AXNode], at point: Point? = nil) {
        guard element.isTextEntry else { return nil }
        identifier = element.normalizedUniqueId
        label = identifier == nil ? element.normalizedLabel : nil
        type = element.type
        guard identifier != nil || label != nil else { return nil }
        // Coordinate targeting is the escape hatch for duplicate labels/ids.
        // Do not turn such a hit into an identity that can never be read back.
        guard let match = self.element(in: roots) else { return nil }
        if let point {
            guard let frame = match.frame,
                  point.x >= frame.x, point.x < frame.x + frame.width,
                  point.y >= frame.y, point.y < frame.y + frame.height else { return nil }
        }
    }

    /// An identifier takes precedence over the label. Ambiguous or differently
    /// typed matches must not verify a write to another field.
    public func element(in roots: [AXNode]) -> AXNode? {
        let matches = roots.flatMap { $0.flattened() }.filter { node in
            guard node.isTextEntry, node.type == type else { return false }
            if let identifier { return node.normalizedUniqueId == identifier }
            return node.normalizedLabel == label
        }
        return matches.count == 1 ? matches.first : nil
    }

    /// A label alone cannot tell the field from another one the layout moved
    /// under the original point, so only an identifier admits a point read.
    public func allowsPointReadback(of node: AXNode) -> Bool {
        guard let identifier, node.isTextEntry, node.type == type else { return false }
        return node.normalizedUniqueId == identifier
    }
}
