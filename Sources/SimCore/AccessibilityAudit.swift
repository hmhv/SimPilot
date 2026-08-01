// AccessibilityAudit.swift
//
// Mechanical accessibility audit over a describe-ui tree.
//
// Xcode ships the same idea as `XCUIApplication.performAccessibilityAudit`, but
// only from inside a UI test target — there is no CLI, no simctl subcommand and
// no devicectl subcommand that will audit a running app. This runs the checks
// that are decidable from the accessibility tree alone, from the command line,
// against any booted simulator, with no test target and no app changes.
//
// Deliberately NOT covered: contrast ratios and clipped text. Both need pixel
// analysis of the rendered frame, and a guess from the AX tree would produce
// false positives that train users to ignore the report. `truncatedText` catches
// the subset of clipping that the guest itself reports via an ellipsis.
//
// Every rule here is decidable, explainable, and points at a specific element.
// Pure Foundation: no SimBridge, no private frameworks, fully unit-testable.

import Foundation

/// How much a finding matters. `error` marks something that breaks the
/// experience for an assistive-technology user (or breaks automation outright);
/// `warning` marks something that degrades it.
public enum A11ySeverity: String, Codable, Sendable, CaseIterable, Comparable {
    case warning
    case error

    private var rank: Int {
        switch self {
        case .warning: return 0
        case .error: return 1
        }
    }

    public static func < (lhs: A11ySeverity, rhs: A11ySeverity) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// The audit rules. Rule ids are kebab-case and stable — reports and saved
/// baselines key off them.
public enum A11yRule: String, Codable, Sendable, CaseIterable {
    /// An actionable control smaller than the 44x44pt minimum touch target.
    case hitRegion = "hit-region"
    /// An actionable control with nothing for VoiceOver to announce.
    case missingLabel = "missing-label"
    /// Several actionable controls share one label, so neither a user nor a
    /// selector can tell them apart.
    case duplicateLabel = "duplicate-label"
    /// A label that carries no meaning: a bare role word, a file name, or a raw
    /// identifier.
    case genericLabel = "generic-label"
    /// Text the guest itself reports as truncated (trailing ellipsis).
    case truncatedText = "truncated-text"

    public var severity: A11ySeverity {
        switch self {
        // `missingLabel` is decidable: the element genuinely announces nothing.
        //
        // `hitRegion` is an INFERENCE. The accessibility frame is a lower bound on
        // the tappable area, not the area itself — a control can report a 20pt
        // glyph frame while its real hit region is the 44pt pill around it
        // (measured: Safari's reload button and address field). Reporting that as
        // an error would put false failures in front of every user and train them
        // to ignore the audit, so it warns and says what it measured.
        case .missingLabel: return .error
        case .hitRegion, .duplicateLabel, .genericLabel, .truncatedText: return .warning
        }
    }

    public var summary: String {
        switch self {
        case .hitRegion: return "Actionable element whose accessibility frame is smaller than the minimum touch target"
        case .missingLabel: return "Actionable element with no accessibility label or value"
        case .duplicateLabel: return "Several actionable elements share one label"
        case .genericLabel: return "Label carries no meaning (role word, file name, or raw identifier)"
        case .truncatedText: return "Text is truncated with an ellipsis"
        }
    }
}

/// One audit finding, anchored to the element that triggered it.
public struct A11yFinding: Equatable, Sendable {
    public let rule: A11yRule
    public let severity: A11ySeverity
    public let message: String
    public let label: String?
    public let identifier: String?
    public let elementType: String?
    public let frame: AXNode.Frame?

    public init(
        rule: A11yRule,
        message: String,
        label: String? = nil,
        identifier: String? = nil,
        elementType: String? = nil,
        frame: AXNode.Frame? = nil
    ) {
        self.rule = rule
        self.severity = rule.severity
        self.message = message
        self.label = label
        self.identifier = identifier
        self.elementType = elementType
        self.frame = frame
    }

    /// Stable JSON shape for reports and CI consumers.
    public var jsonObject: [String: Any] {
        var object: [String: Any] = [
            "rule": rule.rawValue,
            "severity": severity.rawValue,
            "message": message
        ]
        if let label { object["label"] = label }
        if let identifier { object["id"] = identifier }
        if let elementType { object["type"] = elementType }
        if let frame {
            object["frame"] = ["x": frame.x, "y": frame.y, "width": frame.width, "height": frame.height]
        }
        return object
    }
}

public enum AccessibilityAudit {
    /// Apple's Human Interface Guidelines minimum touch target, in points.
    public static let minimumTouchTarget = 44.0

    public struct Options: Sendable {
        /// Minimum touch target edge in points.
        public var minimumTouchTarget: Double
        /// Rules to run. Defaults to all of them.
        public var rules: Set<A11yRule>

        public init(
            minimumTouchTarget: Double = AccessibilityAudit.minimumTouchTarget,
            rules: Set<A11yRule> = Set(A11yRule.allCases)
        ) {
            self.minimumTouchTarget = minimumTouchTarget
            self.rules = rules
        }
    }

    /// Run the audit over a describe-ui tree.
    ///
    /// Findings come back ordered by severity (errors first) then by rule, so the
    /// head of the list is always the most actionable part of the report.
    public static func run(roots: [AXNode], options: Options = Options()) -> [A11yFinding] {
        let elements = roots.flatMap { $0.flattened() }
        var findings: [A11yFinding] = []

        if options.rules.contains(.hitRegion) {
            findings += hitRegionFindings(elements, minimum: options.minimumTouchTarget)
        }
        if options.rules.contains(.missingLabel) {
            findings += missingLabelFindings(elements)
        }
        if options.rules.contains(.duplicateLabel) {
            findings += duplicateLabelFindings(elements)
        }
        if options.rules.contains(.genericLabel) {
            findings += genericLabelFindings(elements)
        }
        if options.rules.contains(.truncatedText) {
            findings += truncatedTextFindings(elements)
        }

        return findings.sorted { left, right in
            if left.severity != right.severity { return left.severity > right.severity }
            if left.rule != right.rule { return left.rule.rawValue < right.rule.rawValue }
            return (left.label ?? "") < (right.label ?? "")
        }
    }

    // MARK: - Rules

    /// Types excluded from the touch-target rule.
    ///
    /// A link inside running text is sized by the text, and Apple's own guidance
    /// exempts it from the 44pt minimum — flagging every inline link would bury
    /// the real findings.
    private static let hitRegionExemptTypes: Set<String> = ["Link"]

    private static func hitRegionFindings(_ elements: [AXNode], minimum: Double) -> [A11yFinding] {
        elements.compactMap { node in
            guard node.isActionable, node.enabled != false, let frame = node.frame else { return nil }
            if let type = node.type, hitRegionExemptTypes.contains(type) { return nil }
            // A zero-extent frame is an element that is not laid out (off screen,
            // hidden, or collapsed) rather than an undersized target.
            guard frame.width > 0, frame.height > 0 else { return nil }
            guard frame.width < minimum || frame.height < minimum else { return nil }
            return A11yFinding(
                rule: .hitRegion,
                message: String(
                    format: "accessibility frame is %.0fx%.0fpt, below the %.0fx%.0fpt minimum "
                        + "(the real hit region may be larger — confirm before filing)",
                    frame.width, frame.height, minimum, minimum
                ),
                label: node.normalizedLabel,
                identifier: node.normalizedUniqueId,
                elementType: node.type,
                frame: frame
            )
        }
    }

    private static func missingLabelFindings(_ elements: [AXNode]) -> [A11yFinding] {
        elements.compactMap { node in
            // Disabled controls are INCLUDED here, unlike the touch-target rule.
            // VoiceOver still reaches and announces them ("dimmed"), so an unlabeled
            // disabled button is exactly as opaque to a screen-reader user as an
            // enabled one — and it is usually the same control a moment later.
            guard node.isActionable else { return nil }
            // An identifier is for automation, not for users — VoiceOver never
            // speaks it — so a node with only an AXUniqueId still counts as unlabeled.
            guard node.normalizedLabel == nil, node.normalizedValue == nil else { return nil }
            return A11yFinding(
                rule: .missingLabel,
                message: "actionable element has no accessibility label or value; VoiceOver announces only its type",
                label: nil,
                identifier: node.normalizedUniqueId,
                elementType: node.type,
                frame: node.frame
            )
        }
    }

    private static func duplicateLabelFindings(_ elements: [AXNode]) -> [A11yFinding] {
        // Group by (label, type): two buttons named "Edit" are ambiguous, but a
        // button and a static text sharing a word are not.
        var groups: [String: [AXNode]] = [:]
        for node in elements where node.isActionable && node.enabled != false {
            guard let label = node.normalizedLabel else { continue }
            // A distinct identifier keeps the element addressable by automation and
            // usually reflects a deliberately repeated control (a list of rows).
            // Only flag the case where nothing else separates them.
            let key = "\(label)\u{0}\(node.type ?? "")"
            groups[key, default: []].append(node)
        }

        return groups.compactMap { _, nodes in
            guard nodes.count > 1 else { return nil }
            let distinctIdentifiers = Set(nodes.compactMap(\.normalizedUniqueId))
            guard distinctIdentifiers.count < nodes.count else { return nil }
            let node = nodes[0]
            return A11yFinding(
                rule: .duplicateLabel,
                message: "\(nodes.count) actionable elements share the label and type with no distinguishing identifier; "
                    + "selectors resolving this label will be ambiguous",
                label: node.normalizedLabel,
                identifier: node.normalizedUniqueId,
                elementType: node.type,
                frame: node.frame
            )
        }
    }

    /// Role words that describe the control instead of what it does.
    private static let roleWords: Set<String> = [
        "button", "image", "icon", "picture", "photo", "graphic", "cell", "item",
        "link", "tab", "view", "label", "text", "field", "switch", "toggle",
        "slider", "control", "element", "untitled", "unknown", "todo", "tbd",
        "placeholder", "asset"
    ]

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "pdf", "svg", "heic", "webp"]

    private static func genericLabelFindings(_ elements: [AXNode]) -> [A11yFinding] {
        elements.compactMap { node in
            // Disabled included, for the same reason as `missing-label`: VoiceOver
            // announces the label either way, so a meaningless one is a defect
            // either way.
            guard node.isActionable, let label = node.normalizedLabel else { return nil }
            guard let reason = genericLabelReason(label) else { return nil }
            return A11yFinding(
                rule: .genericLabel,
                message: "label \"\(label)\" \(reason)",
                label: label,
                identifier: node.normalizedUniqueId,
                elementType: node.type,
                frame: node.frame
            )
        }
    }

    /// Why `label` reads as meaningless, or nil when it is fine. Exposed for tests.
    public static func genericLabelReason(_ label: String) -> String? {
        let lowercased = label.lowercased()

        // A file name shipped straight from the asset catalog.
        if let dotIndex = lowercased.lastIndex(of: "."), dotIndex != lowercased.startIndex {
            let ext = String(lowercased[lowercased.index(after: dotIndex)...])
            if imageExtensions.contains(ext) {
                return "is an image file name, not a description of what the control does"
            }
        }

        // Bare role words, alone or as a short combination ("icon button").
        let words = lowercased.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        if !words.isEmpty, words.count <= 2, words.allSatisfy(roleWords.contains) {
            return "is a role word, which VoiceOver already announces from the element type"
        }

        // A raw identifier leaked into the label: no spaces, and separator/casing
        // structure a human-written label would not have.
        if !label.contains(" "), label.count > 2 {
            if label.contains("_") || label.contains(".") {
                return "looks like a raw identifier rather than human-readable text"
            }
            // camelCase / PascalCase with an interior capital and no spaces.
            let hasInteriorCapital = label.dropFirst().contains { $0.isUppercase }
            let hasLowercase = label.contains { $0.isLowercase }
            if hasInteriorCapital && hasLowercase {
                return "looks like a raw identifier rather than human-readable text"
            }
        }

        return nil
    }

    private static func truncatedTextFindings(_ elements: [AXNode]) -> [A11yFinding] {
        elements.compactMap { node in
            // An ACTIONABLE element's label is exempt. Apple's own convention puts
            // a trailing ellipsis on any control that opens a further prompt —
            // "Save As…", "Move to…", "Rename…" — so treating those as clipped text
            // would flag correct, idiomatic UI on nearly every screen. With
            // `--fail-on warning` that alone would fail an audit of a healthy app.
            //
            // Its VALUE is still checked (a button showing clipped content is a real
            // defect), as is everything about a non-actionable element.
            let candidates = node.isActionable
                ? [node.normalizedValue].compactMap { $0 }
                : [node.normalizedLabel, node.normalizedValue].compactMap { $0 }
            guard let truncated = candidates.first(where: isTruncated) else { return nil }
            return A11yFinding(
                rule: .truncatedText,
                message: "text \"\(truncated)\" is truncated; the full string is unavailable to VoiceOver and to text assertions",
                label: node.normalizedLabel,
                identifier: node.normalizedUniqueId,
                elementType: node.type,
                frame: node.frame
            )
        }
    }

    /// Whether a string ends in an ellipsis the guest inserted. Exposed for tests.
    ///
    /// A trailing "..." is ambiguous — it is also ordinary punctuation — so only the
    /// single-character U+2026 that the text system substitutes when it clips
    /// counts, and only when it is not preceded by a space (the "Move to …" idiom).
    ///
    /// This alone cannot separate clipped text from the "opens a further prompt"
    /// convention, which is written exactly the same way ("Save As…"). The caller
    /// makes that distinction structurally: see `truncatedTextFindings`, which
    /// exempts an actionable element's label.
    public static func isTruncated(_ text: String) -> Bool {
        guard text.hasSuffix("\u{2026}") else { return false }
        let withoutEllipsis = text.dropLast()
        guard let last = withoutEllipsis.last else { return false }
        return !last.isWhitespace
    }

    /// How many elements the audit examined. Reported alongside a clean result so
    /// "no findings" is distinguishable from "nothing was inspected".
    public static func elementCount(roots: [AXNode]) -> Int {
        roots.reduce(0) { $0 + $1.flattened().count }
    }

    /// Count findings by severity, for a report header.
    public static func counts(_ findings: [A11yFinding]) -> [A11ySeverity: Int] {
        findings.reduce(into: [:]) { counts, finding in
            counts[finding.severity, default: 0] += 1
        }
    }
}
