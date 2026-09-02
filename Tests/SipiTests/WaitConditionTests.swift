// WaitConditionTests.swift
//
// Locks `sipi wait-for`'s condition semantics, which are deliberately the
// verify semantics: a text wait is a `contains` (or `absent`) row, an element
// wait is an `elements` row, absence is judged against the deep tree, and a
// presence miss on the fast tree escalates to the deep tree before failing.

import XCTest
import SimCore
@testable import sipi

final class WaitConditionTests: XCTestCase {

    private func capture(_ nodes: [AXNode]) throws -> VerifyEvaluator.Capture {
        VerifyEvaluator.Capture(json: try AXNodeJSON.string(for: nodes), nodes: nodes)
    }

    private let button = AXNode(AXLabel: "Sign In", type: "Button", AXUniqueId: "auth.sign-in")
    private let spinner = AXNode(AXLabel: "Loading", type: "ActivityIndicator")

    func testTextPresenceIsSatisfiedByTheFastTree() throws {
        let condition = WaitCondition(text: "Sign In", absent: false)
        var deepCalls = 0
        let rows = try condition.evaluate(fast: try capture([button])) {
            deepCalls += 1
            return try self.capture([self.button])
        }
        XCTAssertTrue(rows.allSatisfy(\.found))
        XCTAssertEqual(deepCalls, 0, "a fast-tree hit must not pay for the deep pass")
    }

    func testTextPresenceEscalatesToDeepOnAMiss() throws {
        let condition = WaitCondition(text: "Share", absent: false)
        var deepCalls = 0
        let rows = try condition.evaluate(fast: try capture([button])) {
            deepCalls += 1
            return try self.capture([self.button, AXNode(AXLabel: "Share", type: "Button")])
        }
        XCTAssertTrue(rows.allSatisfy(\.found))
        XCTAssertEqual(deepCalls, 1)
    }

    func testTextAbsenceIsJudgedAgainstTheDeepTree() throws {
        let condition = WaitCondition(text: "Loading", absent: true)
        // Fast tree looks clean, deep tree still shows the spinner: not satisfied.
        let rows = try condition.evaluate(fast: try capture([button])) {
            try self.capture([self.button, self.spinner])
        }
        XCTAssertFalse(rows.allSatisfy(\.found))
        XCTAssertEqual(rows.first?.check, "absent: Loading")
    }

    func testElementWaitMatchesExactlyAndHonoursType() throws {
        let condition = WaitCondition(label: "Sign In", elementType: "Button", absent: false)
        XCTAssertTrue(try condition.evaluate(fast: try capture([button])) { try self.capture([]) }.allSatisfy(\.found))

        let wrongType = WaitCondition(label: "Sign In", elementType: "Cell", absent: false)
        let rows = try wrongType.evaluate(fast: try capture([button])) { try self.capture([self.button]) }
        XCTAssertFalse(rows.allSatisfy(\.found))
        XCTAssertEqual(rows.first?.grepMatch, "no element matched")
    }

    func testElementAbsenceUsesExistsFalse() throws {
        let condition = WaitCondition(id: "auth.sign-in", absent: true)
        XCTAssertEqual(condition.description, "element: id=auth.sign-in [absent]")
        let gone = try condition.evaluate(fast: try capture([button])) { try self.capture([self.spinner]) }
        XCTAssertTrue(gone.allSatisfy(\.found))
        let still = try condition.evaluate(fast: try capture([])) { try self.capture([self.button]) }
        XCTAssertFalse(still.allSatisfy(\.found))
    }

    func testDescriptionsReadLikeVerifyRows() {
        XCTAssertEqual(WaitCondition(text: "Done", absent: false).description, "contains: Done")
        XCTAssertEqual(WaitCondition(text: "Done", absent: true).description, "absent: Done")
        XCTAssertEqual(
            WaitCondition(label: "OK", elementType: "Button", absent: false).description,
            "element: label=OK type=Button [exists]")
    }

    // MARK: - Option validation

    func testExactlyOneNonEmptySelectorIsRequired() {
        typealias W = Sipi.WaitFor
        XCTAssertNil(W.selectionProblem(label: "OK", id: nil, value: nil, text: nil, elementType: "Button"))
        XCTAssertNil(W.selectionProblem(label: nil, id: nil, value: nil, text: "Done", elementType: nil))
        XCTAssertNotNil(W.selectionProblem(label: nil, id: nil, value: nil, text: nil, elementType: nil))
        XCTAssertNotNil(W.selectionProblem(label: "A", id: "b", value: nil, text: nil, elementType: nil))
        XCTAssertNotNil(W.selectionProblem(label: nil, id: nil, value: nil, text: "Done", elementType: "Button"),
                        "--element-type has no meaning with --text")
    }

    func testEmptyOrWhitespaceSelectorsAreRejectedBecauseTheyMatchEverything() {
        typealias W = Sipi.WaitFor
        // `"…".contains("")` is always true: an empty --text would report a
        // screen it never tested.
        XCTAssertNotNil(W.selectionProblem(label: nil, id: nil, value: nil, text: "", elementType: nil))
        XCTAssertNotNil(W.selectionProblem(label: nil, id: nil, value: nil, text: "  \n", elementType: nil))
        XCTAssertNotNil(W.selectionProblem(label: " ", id: nil, value: nil, text: nil, elementType: nil))
        XCTAssertNotNil(W.selectionProblem(label: nil, id: "", value: nil, text: nil, elementType: nil))
    }

    func testSelectorsAreTrimmedTheWayTheTreeIsReadButTextStaysVerbatim() throws {
        let padded = WaitCondition.from(label: " Sign In ", id: nil, value: nil, text: nil, elementType: " Button ", absent: false)
        XCTAssertEqual(padded.label, "Sign In")
        XCTAssertEqual(padded.elementType, "Button")
        XCTAssertTrue(try padded.evaluate(fast: try capture([button])) { try self.capture([]) }.allSatisfy(\.found))

        // With --absent, an untrimmed label would have "found" nothing and passed
        // over an element that is plainly on screen.
        let absent = WaitCondition.from(label: " Sign In ", id: nil, value: nil, text: nil, elementType: nil, absent: true)
        XCTAssertFalse(try absent.evaluate(fast: try capture([button])) { try self.capture([self.button]) }.allSatisfy(\.found))

        let text = WaitCondition.from(label: nil, id: nil, value: nil, text: " Sign ", elementType: nil, absent: false)
        XCTAssertEqual(text.text, " Sign ", "a substring keeps its spaces; they are part of what is searched for")
    }
}
