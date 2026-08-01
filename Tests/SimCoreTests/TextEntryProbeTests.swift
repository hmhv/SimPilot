// TextEntryProbeTests.swift
//
// Locks the no-op detection for `type`. The rule that matters most is the one
// that motivated the whole probe: the fingerprint must ignore everything except
// text-entry content, because the status bar clock is in the tree and a
// whole-tree comparison would report a change every second — passing the check
// on a runtime that delivered nothing.

import XCTest
@testable import SimCore

final class TextEntryProbeTests: XCTestCase {

    private func field(_ value: String?, id: String? = "field.1", type: String = "TextField") -> AXNode {
        AXNode(AXValue: value, role: "AX" + type, type: type, AXUniqueId: id, enabled: true)
    }

    private func clock(_ time: String) -> AXNode {
        AXNode(AXLabel: time, role: "AXStaticText", type: "StaticText", enabled: true)
    }

    func testFingerprintIsNilWithoutTextEntryElement() {
        XCTAssertNil(TextEntryProbe.fingerprint(roots: [clock("9:41")]))
        XCTAssertNil(TextEntryProbe.fingerprint(roots: []))
    }

    func testFingerprintTracksTextEntryValue() {
        let before = TextEntryProbe.fingerprint(roots: [field("")])
        let after = TextEntryProbe.fingerprint(roots: [field("hello")])
        XCTAssertNotNil(before)
        XCTAssertNotEqual(before, after)
    }

    /// The regression this probe exists for: a ticking clock must not read as
    /// evidence that text arrived.
    func testClockChangeDoesNotLookLikeTextEntry() {
        let before = TextEntryProbe.fingerprint(roots: [clock("9:41"), field("")])
        let after = TextEntryProbe.fingerprint(roots: [clock("9:42"), field("")])
        XCTAssertEqual(before, after, "a status-bar clock tick must not register as a text change")
        XCTAssertEqual(TextEntryProbe.failureReason(before: before, after: after), .unchanged)
    }

    func testEveryTextEntryTypeIsTracked() {
        for type in ["TextField", "SecureTextField", "TextView", "TextArea", "SearchField", "ComboBox"] {
            XCTAssertNotNil(
                TextEntryProbe.fingerprint(roots: [field("x", type: type)]),
                "\(type) should count as a text-entry element")
        }
    }

    /// A secure field reports bullets rather than the written text, but bullets
    /// still differ from empty — the check must accept that as evidence.
    func testSecureFieldBulletsCountAsChange() {
        let before = TextEntryProbe.fingerprint(roots: [field("", type: "SecureTextField")])
        let after = TextEntryProbe.fingerprint(roots: [field("••••", type: "SecureTextField")])
        XCTAssertNil(TextEntryProbe.failureReason(before: before, after: after))
    }

    func testNilBeforeMeansNowhereToType() {
        XCTAssertEqual(
            TextEntryProbe.failureReason(before: nil, after: "anything"),
            .noTextEntryElement)
    }

    /// A field that vanished (the keyboard dismissed, a sheet closed) is a change,
    /// not a no-op — failing there would flag a working step.
    func testFieldDisappearingIsNotAFailure() {
        XCTAssertNil(TextEntryProbe.failureReason(before: "field.1\u{0}\u{0}", after: nil))
    }

    /// Replacing one field with a different field holding the same text is a
    /// change, which is why identity is part of the fingerprint.
    func testIdentityIsPartOfTheFingerprint() {
        let before = TextEntryProbe.fingerprint(roots: [field("same", id: "a")])
        let after = TextEntryProbe.fingerprint(roots: [field("same", id: "b")])
        XCTAssertNotEqual(before, after)
    }

    func testMultipleFieldsAreAllTracked() {
        let before = TextEntryProbe.fingerprint(roots: [field("", id: "a"), field("", id: "b")])
        let after = TextEntryProbe.fingerprint(roots: [field("", id: "a"), field("typed", id: "b")])
        XCTAssertEqual(TextEntryProbe.failureReason(before: before, after: after), nil)
    }

    func testNestedFieldsAreFound() {
        let root = AXNode(type: "Window", children: [AXNode(type: "Group", children: [field("nested")])])
        XCTAssertNotNil(TextEntryProbe.fingerprint(roots: [root]))
    }
}
