// AccessibilityAuditTests.swift
//
// Locks the audit rules, and — just as important — the cases each rule must NOT
// flag. A noisy audit is an ignored audit, so every rule has a negative test
// beside its positive one.

import XCTest
@testable import SimCore

final class AccessibilityAuditTests: XCTestCase {

    private func button(
        label: String? = "Sign In",
        id: String? = nil,
        value: String? = nil,
        enabled: Bool? = true,
        width: Double = 100,
        height: Double = 44,
        type: String = "Button"
    ) -> AXNode {
        AXNode(
            AXLabel: label,
            AXValue: value,
            role: "AX" + type,
            type: type,
            AXUniqueId: id,
            enabled: enabled,
            frame: AXNode.Frame(x: 0, y: 0, width: width, height: height)
        )
    }

    // MARK: - hit-region

    func testFlagsUndersizedTouchTarget() {
        let findings = AccessibilityAudit.run(roots: [button(width: 30, height: 30)])
        XCTAssertEqual(findings.map(\.rule), [.hitRegion])
        // A warning, not an error: the accessibility frame is a lower bound on the
        // tappable area, so this is an inference the author must confirm.
        XCTAssertEqual(findings.first?.severity, .warning)
    }

    /// An inline text link is sized by its text and is exempt from the 44pt
    /// minimum; flagging every one of them would bury the real findings.
    func testInlineLinkIsExemptFromTouchTargetRule() {
        let findings = AccessibilityAudit.run(
            roots: [button(label: "Learn more", width: 83, height: 21, type: "Link")])
        XCTAssertFalse(findings.contains { $0.rule == .hitRegion }, "\(findings)")
    }

    func testAcceptsExactlyMinimumTouchTarget() {
        let findings = AccessibilityAudit.run(roots: [button(width: 44, height: 44)])
        XCTAssertTrue(findings.isEmpty, "\(findings)")
    }

    /// A zero-extent frame is an element that is not laid out, not an undersized
    /// target — flagging it would fire on every off-screen control.
    func testIgnoresZeroExtentFrame() {
        let findings = AccessibilityAudit.run(roots: [button(width: 0, height: 0)])
        XCTAssertTrue(findings.isEmpty, "\(findings)")
    }

    func testIgnoresNonActionableSmallElement() {
        let text = AXNode(
            AXLabel: "Caption", role: "AXStaticText", type: "StaticText",
            enabled: true, frame: AXNode.Frame(x: 0, y: 0, width: 20, height: 12))
        XCTAssertTrue(AccessibilityAudit.run(roots: [text]).isEmpty)
    }

    func testIgnoresDisabledControl() {
        let findings = AccessibilityAudit.run(roots: [button(enabled: false, width: 10, height: 10)])
        XCTAssertTrue(findings.isEmpty, "\(findings)")
    }

    func testHonorsCustomMinimumTouchTarget() {
        let findings = AccessibilityAudit.run(
            roots: [button(width: 40, height: 40)],
            options: AccessibilityAudit.Options(minimumTouchTarget: 32))
        XCTAssertTrue(findings.isEmpty, "\(findings)")
    }

    // MARK: - missing-label

    func testFlagsActionableElementWithNoLabelOrValue() {
        let findings = AccessibilityAudit.run(roots: [button(label: nil, id: "cta.submit")])
        XCTAssertEqual(findings.map(\.rule), [.missingLabel])
    }

    /// An identifier is for automation; VoiceOver never speaks it, so it does not
    /// satisfy the label requirement — but a value does.
    func testValueSatisfiesLabelRequirement() {
        let findings = AccessibilityAudit.run(roots: [button(label: nil, value: "42")])
        XCTAssertTrue(findings.isEmpty, "\(findings)")
    }

    /// Unlike the touch-target rule, this one covers disabled controls: VoiceOver
    /// still reaches and announces them ("dimmed"), so an unlabeled disabled
    /// button is exactly as opaque as an enabled one.
    func testFlagsDisabledElementWithNoLabel() {
        let findings = AccessibilityAudit.run(roots: [button(label: nil, enabled: false)])
        XCTAssertEqual(findings.map(\.rule), [.missingLabel])
    }

    func testFlagsMeaninglessLabelOnDisabledElement() {
        let findings = AccessibilityAudit.run(roots: [button(label: "cart_icon.png", enabled: false)])
        XCTAssertEqual(findings.map(\.rule), [.genericLabel])
    }

    // MARK: - duplicate-label

    func testFlagsDuplicateLabelWithoutDistinguishingIdentifier() {
        let findings = AccessibilityAudit.run(roots: [button(label: "Edit"), button(label: "Edit")])
        XCTAssertEqual(findings.map(\.rule), [.duplicateLabel])
        XCTAssertEqual(findings.first?.severity, .warning)
    }

    func testDistinctIdentifiersSuppressDuplicateLabel() {
        let findings = AccessibilityAudit.run(roots: [
            button(label: "Edit", id: "row.1.edit"),
            button(label: "Edit", id: "row.2.edit")
        ])
        XCTAssertTrue(findings.isEmpty, "\(findings)")
    }

    func testSameLabelOnDifferentTypesIsNotDuplicate() {
        let findings = AccessibilityAudit.run(roots: [
            button(label: "Search", type: "Button"),
            button(label: "Search", type: "TextField")
        ])
        XCTAssertTrue(findings.isEmpty, "\(findings)")
    }

    // MARK: - generic-label

    func testFlagsRoleWordLabel() {
        XCTAssertNotNil(AccessibilityAudit.genericLabelReason("Button"))
        XCTAssertNotNil(AccessibilityAudit.genericLabelReason("icon button"))
    }

    func testFlagsImageFileNameLabel() {
        XCTAssertNotNil(AccessibilityAudit.genericLabelReason("cart_icon.png"))
    }

    func testFlagsRawIdentifierLabel() {
        XCTAssertNotNil(AccessibilityAudit.genericLabelReason("auth_sign_in"))
        XCTAssertNotNil(AccessibilityAudit.genericLabelReason("signInButton"))
    }

    func testAcceptsHumanReadableLabels() {
        for label in ["Sign In", "Add to cart", "Play", "音量", "Done", "OK"] {
            XCTAssertNil(AccessibilityAudit.genericLabelReason(label), "false positive on \(label)")
        }
    }

    /// An all-caps acronym is a legitimate label, not an identifier: it has no
    /// interior lowercase, so the camelCase heuristic must not claim it.
    func testAcceptsAcronymLabel() {
        XCTAssertNil(AccessibilityAudit.genericLabelReason("PDF"))
        XCTAssertNil(AccessibilityAudit.genericLabelReason("OK"))
    }

    // MARK: - truncated-text

    func testFlagsEllipsisTruncation() {
        XCTAssertTrue(AccessibilityAudit.isTruncated("A very long headline that got cut\u{2026}"))
    }

    /// "Move to…" is the idiom for "this opens a further prompt", not clipping.
    /// The space before the ellipsis is what distinguishes them.
    func testDoesNotFlagDeliberateEllipsisIdiom() {
        XCTAssertFalse(AccessibilityAudit.isTruncated("Move to \u{2026}"))
    }

    /// Three periods are ordinary punctuation and are not what the text system
    /// substitutes when it clips.
    func testDoesNotFlagThreeDots() {
        XCTAssertFalse(AccessibilityAudit.isTruncated("Loading..."))
    }

    /// Apple's convention puts a trailing ellipsis on any control that opens a
    /// further prompt. Those labels are written exactly like clipped text, so the
    /// distinction has to be structural: an actionable element's LABEL is exempt.
    /// Without this, `--fail-on warning` would fail an audit of a healthy app.
    func testDoesNotFlagFurtherPromptButtonLabels() {
        for label in ["Save As\u{2026}", "Move to\u{2026}", "Rename\u{2026}"] {
            let findings = AccessibilityAudit.run(roots: [button(label: label)])
            XCTAssertFalse(
                findings.contains { $0.rule == .truncatedText },
                "\(label) is the further-action idiom, not clipped text: \(findings)")
        }
    }

    /// The exemption is scoped to the label. A control whose VALUE is clipped is a
    /// real defect and still reported.
    func testFlagsTruncatedValueOnActionableElement() {
        let findings = AccessibilityAudit.run(
            roots: [button(label: "Note", value: "A very long note that got cut\u{2026}")])
        XCTAssertTrue(findings.contains { $0.rule == .truncatedText }, "\(findings)")
    }

    /// Non-actionable text has no such convention, so its label is still checked.
    func testFlagsTruncatedStaticTextLabel() {
        let text = AXNode(
            AXLabel: "A very long headline that got cut\u{2026}",
            role: "AXStaticText", type: "StaticText", enabled: true,
            frame: AXNode.Frame(x: 0, y: 0, width: 300, height: 20))
        XCTAssertTrue(
            AccessibilityAudit.run(roots: [text]).contains { $0.rule == .truncatedText })
    }

    // MARK: - ordering and counts

    func testErrorsSortBeforeWarnings() {
        let findings = AccessibilityAudit.run(roots: [
            button(label: "Button", width: 100, height: 44),   // generic-label (warning)
            button(label: nil, width: 10, height: 10)          // missing-label + hit-region (errors)
        ])
        let severities = findings.map(\.severity)
        XCTAssertEqual(severities, severities.sorted(by: >), "errors must come first: \(findings.map(\.rule))")
    }

    func testCountsBySeverity() {
        // One unlabeled, undersized button yields both rules: missing-label
        // (error, decidable) and hit-region (warning, an inference).
        let findings = AccessibilityAudit.run(roots: [button(label: nil, width: 10, height: 10)])
        let counts = AccessibilityAudit.counts(findings)
        XCTAssertEqual(counts[.error], 1)
        XCTAssertEqual(counts[.warning], 1)
    }

    func testRuleSubsetRunsOnlySelectedRules() {
        let findings = AccessibilityAudit.run(
            roots: [button(label: nil, width: 10, height: 10)],
            options: AccessibilityAudit.Options(rules: [.hitRegion]))
        XCTAssertEqual(findings.map(\.rule), [.hitRegion])
    }

    func testElementCountIncludesDescendants() {
        let parent = AXNode(type: "Other", children: [button(), button()])
        XCTAssertEqual(AccessibilityAudit.elementCount(roots: [parent]), 3)
    }
}
