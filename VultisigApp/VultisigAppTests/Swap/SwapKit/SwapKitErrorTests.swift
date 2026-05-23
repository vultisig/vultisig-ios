//
//  SwapKitErrorTests.swift
//  VultisigAppTests
//
//  Locks the upstream `error` code → `SwapKitError` mapping. New error
//  codes get a row here; collapsed codes (e.g. `failedToRetrieveBalance`
//  folding into `unableToBuildTransaction`) get pinned so the friendlier
//  user-facing copy survives refactors.
//

import XCTest
@testable import VultisigApp

final class SwapKitErrorTests: XCTestCase {

    // MARK: - Documented error codes

    func testInsufficientBalanceMaps() {
        XCTAssertEqual(decode("insufficientBalance"), .insufficientBalance)
    }

    func testNoRoutesFoundMaps() {
        XCTAssertEqual(decode("noRoutesFound"), .noRoutesFound)
    }

    func testUnableToBuildTransactionMaps() {
        XCTAssertEqual(decode("unableToBuildTransaction"), .unableToBuildTransaction)
    }

    // MARK: - `failedToRetrieveBalance` collapse

    /// SwapKit's NEAR-Intents proxy collapses upstream UTXO-indexer failures
    /// into the literal string `failedToRetrieveBalance`. The user-facing
    /// meaning is the same as `unableToBuildTransaction` — this route is
    /// currently unavailable, try another provider — so the two codes
    /// share one mapped case. The raw string would otherwise leak an
    /// implementation detail and read confusingly as "your balance lookup
    /// failed".
    func testFailedToRetrieveBalanceMapsToUnableToBuildTransaction() {
        XCTAssertEqual(decode("failedToRetrieveBalance"), .unableToBuildTransaction)
    }

    func testFailedToRetrieveBalanceFromHttpDataMapsToUnableToBuildTransaction() throws {
        let body = #"{"error":"failedToRetrieveBalance","message":"Failed to retrieve balance.","data":{"chain":"BCH.BCH"}}"#
        let data = try XCTUnwrap(body.data(using: .utf8))
        let mapped = try XCTUnwrap(SwapKitError.from(httpData: data))
        XCTAssertEqual(mapped, .unableToBuildTransaction)
    }

    // MARK: - Generic fallback

    func testUnknownCodePreservesMessage() {
        let envelope = SwapKitErrorEnvelope(error: "futureCodeWeDontKnowYet", message: "Hello from the future")
        let err = SwapKitError(envelope: envelope)
        XCTAssertEqual(err, .generic(message: "Hello from the future"))
    }

    func testUnknownCodeWithoutMessageEchoesCode() {
        let envelope = SwapKitErrorEnvelope(error: "futureCodeWeDontKnowYet", message: nil)
        let err = SwapKitError(envelope: envelope)
        XCTAssertEqual(err, .generic(message: "futureCodeWeDontKnowYet"))
    }

    // MARK: - Helper

    private func decode(_ code: String) -> SwapKitError? {
        SwapKitError(envelope: SwapKitErrorEnvelope(error: code, message: nil))
    }
}
