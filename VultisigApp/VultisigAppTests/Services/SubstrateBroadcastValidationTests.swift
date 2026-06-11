//
//  SubstrateBroadcastValidationTests.swift
//  VultisigAppTests
//
//  Covers the substrate broadcast-result validator that backs Polkadot and
//  Bittensor. `RpcService.sendRPCRequest` surfaces a rejected extrinsic's
//  `error.message` as a plain string; without validation that string was
//  persisted and polled as a fake txid. The validator accepts only a real
//  extrinsic hash or the duplicate-broadcast sentinel, throwing otherwise.
//

@testable import VultisigApp
import XCTest

final class SubstrateBroadcastValidationTests: XCTestCase {

    func testAcceptsZeroPrefixedExtrinsicHash() throws {
        let hash = "0x" + String(repeating: "a", count: 64)
        XCTAssertEqual(try SubstrateBroadcast.validatedHash(hash), hash)
    }

    func testAcceptsUnprefixedExtrinsicHash() throws {
        let hash = String(repeating: "b", count: 64)
        XCTAssertEqual(try SubstrateBroadcast.validatedHash(hash), hash)
    }

    func testAcceptsDuplicateBroadcastSentinel() throws {
        let sentinel = SubstrateBroadcast.alreadyBroadcastedSentinel
        XCTAssertEqual(try SubstrateBroadcast.validatedHash(sentinel), sentinel)
    }

    func testThrowsOnErrorMessageInsteadOfReturningItAsTxid() {
        XCTAssertThrowsError(try SubstrateBroadcast.validatedHash("Invalid extrinsic")) { error in
            guard case RpcServiceError.rpcError = error else {
                return XCTFail("expected RpcServiceError.rpcError, got \(error)")
            }
        }
    }

    func testThrowsOnEmptyResult() {
        XCTAssertThrowsError(try SubstrateBroadcast.validatedHash(""))
    }

    func testThrowsOnWrongLengthHash() {
        // 63 hex chars — one short of a 32-byte hash.
        XCTAssertThrowsError(try SubstrateBroadcast.validatedHash(String(repeating: "c", count: 63)))
    }

    func testThrowsOnNonHexCharactersOfHashLength() {
        // 64 chars but not all hex digits ('z' is never a hex digit).
        XCTAssertThrowsError(try SubstrateBroadcast.validatedHash(String(repeating: "z", count: 64)))
    }
}
