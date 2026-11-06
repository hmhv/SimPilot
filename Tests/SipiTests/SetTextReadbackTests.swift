import Foundation
import XCTest
import SimCore
@testable import sipi

final class SetTextReadbackTests: XCTestCase {
    private func field(
        _ value: String, id: String? = "field", label: String? = "Name",
        type: String = "TextField", y: Double = 300
    ) -> AXNode {
        AXNode(AXLabel: label, AXValue: value, type: type, AXUniqueId: id,
               frame: .init(x: 10, y: y, width: 200, height: 40))
    }

    private func identity(for element: AXNode) -> TextEntryIdentity? {
        TextEntryIdentity(element: element, in: [element])
    }

    func testIdentityFollowsFieldWhenKeyboardMovesItAndLabelChanges() throws {
        let identity = try XCTUnwrap(identity(for: field("old")))
        let moved = field("日本語🙂", label: "Updated name", y: 100)
        let unrelated = field("", id: "other", y: 300)
        XCTAssertEqual(identity.element(in: [unrelated, moved])?.AXValue, "日本語🙂")
    }

    func testIdentifierDoesNotFallBackToAnotherFieldsMatchingLabel() throws {
        let identity = try XCTUnwrap(identity(for: field("old")))
        XCTAssertNil(identity.element(in: [field("expected", id: "other")]))
    }

    func testDuplicateIdentityCannotVerifyAnotherField() throws {
        let identity = try XCTUnwrap(identity(for: field("old")))
        XCTAssertNil(identity.element(in: [field("expected"), field("old", y: 400)]))
    }

    func testStaticTextAndDifferentFieldTypeCannotVerifyAWrite() throws {
        let identity = try XCTUnwrap(identity(for: field("old")))
        XCTAssertNil(identity.element(in: [field("expected", type: "StaticText")]))
        XCTAssertNil(identity.element(in: [field("expected", type: "SecureTextField")]))
        XCTAssertNil(self.identity(for: field("old", type: "StaticText")))
    }

    func testUniqueLabelFindsNestedFieldWithoutIdentifier() throws {
        let identity = try XCTUnwrap(identity(for: field("old", id: nil)))
        let root = AXNode(type: "Application", children: [field("expected", id: nil, y: 100)])
        XCTAssertEqual(identity.element(in: [root])?.AXValue, "expected")
        XCTAssertNil(identity.element(in: [root, field("other", id: nil)]))
    }

    func testAnonymousFieldRequiresPointReadback() {
        XCTAssertNil(identity(for: field("old", id: nil, label: nil)))
    }

    func testDuplicateLabelsAndIdentifiersKeepCoordinateReadbackUsable() {
        for source in [field("expected", id: nil), field("expected", label: "Item 1")] {
            let other = field("old", id: source.AXUniqueId, label: source.AXUniqueId == nil ? "Name" : "Item 2", y: 400)
            let identity = TextEntryIdentity(element: source, in: [source, other], at: Point(x: 20, y: 320))
            XCTAssertNil(identity)
            let value = guestValue(
                udid: "unused", at: Point(x: 20, y: 320), identity: identity,
                readTree: { _ in XCTFail("An ambiguous identity must retain point readback"); return [] },
                readPoint: { source }
            )
            XCTAssertEqual(value, "expected")
        }
    }

    func testCoordinateIdentityRequiresTheTreeFieldToContainTheHitPoint() {
        let source = field("old")
        XCTAssertNotNil(TextEntryIdentity(element: source, in: [source], at: Point(x: 20, y: 320)))
        XCTAssertNil(TextEntryIdentity(element: source, in: [source], at: Point(x: 20, y: 100)))
    }

    func testTreeReadbackEscalatesToDeepBeforeUsingTheOldPoint() throws {
        let identity = try XCTUnwrap(identity(for: field("old")))
        var reads: [Bool] = []
        let value = guestValue(
            udid: "unused", at: Point(x: 20, y: 320), identity: identity,
            readTree: { deep in
                reads.append(deep)
                return deep ? [self.field("expected", y: 100)] : []
            },
            readPoint: { XCTFail("The old point must not override an identified field"); return nil }
        )
        XCTAssertEqual(value, "expected")
        XCTAssertEqual(reads, [false, true])
    }

    func testLabelOnlyIdentityNeverReadsAnotherFieldAtTheOldPoint() throws {
        let identity = try XCTUnwrap(identity(for: field("old", id: nil)))
        let other = field("expected", id: nil, label: "Email")
        XCTAssertNil(guestValue(
            udid: "unused", at: Point(x: 20, y: 320), identity: identity,
            readTree: { _ in [] }, readPoint: { other }
        ))
    }

    func testPointFallbackReadsOnlyTheSameIdentifierAndType() throws {
        let identity = try XCTUnwrap(identity(for: field("old")))
        for wrong in [field("expected", id: "other"), field("expected", type: "StaticText")] {
            XCTAssertNil(guestValue(
                udid: "unused", at: Point(x: 20, y: 320), identity: identity,
                readTree: { _ in [] }, readPoint: { wrong }
            ))
        }
        XCTAssertEqual(guestValue(
            udid: "unused", at: Point(x: 20, y: 320), identity: identity,
            readTree: { _ in [] }, readPoint: { self.field("old") }
        ), "old")
    }

    func testSuccessfulFastTreeReadDoesNotPayForDeepOrPoint() throws {
        let identity = try XCTUnwrap(identity(for: field("old")))
        var reads: [Bool] = []
        XCTAssertEqual(guestValue(
            udid: "unused", at: Point(x: 20, y: 320), identity: identity,
            readTree: { deep in reads.append(deep); return [self.field("expected", y: 100)] },
            readPoint: { XCTFail("A successful tree read needs no point read"); return nil }
        ), "expected")
        XCTAssertEqual(reads, [false])
    }

    private func outcome(_ values: [String?], expected: String = "expected") -> SetTextOutcome {
        var index = 0
        return verifySetText(
            udid: "unused", at: Point(x: 0, y: 0), expected: expected,
            attempts: values.count, delay: 0,
            readValue: {
                defer { index += 1 }
                return values[index]
            }
        )
    }

    func testStaleOrUnavailableReadCanRecover() {
        XCTAssertEqual(outcome(["old", nil, "expected"]), .matched)
    }

    func testUnchangedValueStillFails() {
        XCTAssertEqual(outcome(["old", "old", "old"]), .mismatch(observed: "old"))
    }

    func testLastUnreadableSampleIsNotReportedAsAnIgnoredWrite() {
        XCTAssertEqual(outcome(["old", nil, nil]), .unreadable)
        XCTAssertEqual(outcome([nil, nil, nil]), .unreadable)
    }

    func testCommandDistinguishesSuccessMismatchAndUnreadableMessages() {
        XCTAssertNil(SetTextOutcome.matched.failureMessage(expected: "expected", udid: "device"))
        let unreadable = SetTextOutcome.unreadable.failureMessage(expected: "expected", udid: "device") ?? ""
        XCTAssertTrue(unreadable.contains("write was sent"))
        XCTAssertTrue(unreadable.contains("sipi describe-ui device"))
        XCTAssertFalse(unreadable.contains("did not take"))
        let mismatch = SetTextOutcome.mismatch(observed: "old").failureMessage(expected: "expected", udid: "device") ?? ""
        XCTAssertTrue(mismatch.contains("did not take"))
        XCTAssertTrue(mismatch.contains("'old'"))
    }
}
