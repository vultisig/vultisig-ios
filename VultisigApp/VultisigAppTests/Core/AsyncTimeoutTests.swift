//
//  AsyncTimeoutTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

final class AsyncTimeoutTests: XCTestCase {
    private enum StubError: Error {
        case boom
    }

    func testReturnsTheValueWhenTheOperationBeatsTheDeadline() async throws {
        let value = try await withTimeout(seconds: 5) { 42 }
        XCTAssertEqual(value, 42)
    }

    func testPropagatesTheOperationErrorRatherThanTheTimeout() async {
        do {
            _ = try await withTimeout(seconds: 5) { throw StubError.boom }
            XCTFail("Expected the operation's own error to propagate.")
        } catch is AsyncTimeoutError {
            XCTFail("A fast failure must not be reported as a timeout.")
        } catch {
            XCTAssertTrue(error is StubError)
        }
    }

    func testThrowsTimeoutWhenTheDeadlineWins() async {
        do {
            _ = try await withTimeout(seconds: 0.05) {
                try await Task.sleep(for: .seconds(30))
                return 1
            }
            XCTFail("Expected a timeout.")
        } catch {
            XCTAssertTrue(error is AsyncTimeoutError, "Got \(error)")
        }
    }

    /// The point of the utility: it returns on the deadline even when the
    /// operation refuses to stop, instead of waiting for the operation to finish.
    func testReturnsOnDeadlineEvenWhenTheOperationIgnoresCancellation() async {
        let operationDuration: TimeInterval = 3
        let start = Date()

        do {
            _ = try await withTimeout(seconds: 0.1) {
                // Uncancellable on purpose — Thread.sleep never checks for
                // cancellation, standing in for a wedged non-cooperative call.
                Thread.sleep(forTimeInterval: operationDuration)
                return 1
            }
            XCTFail("Expected a timeout.")
        } catch {
            XCTAssertTrue(error is AsyncTimeoutError, "Got \(error)")
        }

        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(
            elapsed,
            operationDuration,
            "withTimeout must not wait for a non-cooperative operation to finish."
        )
    }
}
