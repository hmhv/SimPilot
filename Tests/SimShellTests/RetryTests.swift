// RetryTests.swift
//
// Locks the retry helper behind the pasteboard calls (`pbcopy`/`pbpaste`), which
// the default `type` path depends on: a transient simctl failure there used to
// fail an otherwise-good test step. Pure closures — no simulator involved.

import Foundation
import XCTest
@testable import SimShell

final class RetryTests: XCTestCase {
    private struct Boom: Error, Equatable {
        var attempt: Int
    }

    func testSucceedsOnFirstAttemptWithoutRetrying() throws {
        var calls = 0
        let value = try SimShell.retrying(attempts: 3, delay: 0) {
            calls += 1
            return "ok"
        }
        XCTAssertEqual(value, "ok")
        XCTAssertEqual(calls, 1, "a successful call must not be repeated")
    }

    func testRetriesUntilSuccess() throws {
        var calls = 0
        let value = try SimShell.retrying(attempts: 3, delay: 0) { () throws -> String in
            calls += 1
            if calls < 3 { throw Boom(attempt: calls) }
            return "recovered"
        }
        XCTAssertEqual(value, "recovered")
        XCTAssertEqual(calls, 3)
    }

    /// The LAST error must surface: the caller reports simctl's real stderr, not a
    /// synthesized "retries exhausted" message that hides it.
    func testRethrowsLastErrorAfterExhaustingAttempts() {
        var calls = 0
        do {
            _ = try SimShell.retrying(attempts: 3, delay: 0) { () throws -> String in
                calls += 1
                throw Boom(attempt: calls)
            }
            XCTFail("expected the final error to be rethrown")
        } catch let error as Boom {
            XCTAssertEqual(error, Boom(attempt: 3))
        } catch {
            XCTFail("unexpected error \(error)")
        }
        XCTAssertEqual(calls, 3)
    }

    func testPasteboardRetryBudgetIsMoreThanOneAttempt() {
        XCTAssertGreaterThan(SimShell.pasteboardAttempts, 1)
        XCTAssertGreaterThan(SimShell.pasteboardRetryDelay, 0)
    }
}
