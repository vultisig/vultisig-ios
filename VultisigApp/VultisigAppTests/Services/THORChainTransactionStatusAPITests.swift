//
//  THORChainTransactionStatusAPITests.swift
//  VultisigAppTests
//
//  Pins the on-wire `?txid=` contract for Midgard's `/v2/actions`.
//
//  ⚠️ Midgard keys every chain's txid as uppercase hex with NO `0x` prefix.
//  THORChain-native hashes already satisfy that — which is why they resolved —
//  but an EVM-sourced order's inbound hash arrives `0x`-prefixed and lowercase.
//  Sent verbatim it matched nothing, so an L1-sourced limit order's lookup
//  returned an empty page and the order never reached a terminal state. These
//  tests pin the normalization that fixes it, and that it leaves a native hash
//  unchanged.
//

import XCTest
@testable import VultisigApp

final class THORChainTransactionStatusAPITests: XCTestCase {

    private enum TaskShapeError: Error { case notRequestParameters }

    private func txid(forHash hash: String) throws -> String {
        let task = THORChainTransactionStatusAPI.getActions(txHash: hash, chain: .thorChain).task
        guard case let .requestParameters(params, .urlEncoding) = task else {
            XCTFail("getActions must build url-encoded requestParameters")
            throw TaskShapeError.notRequestParameters
        }
        return try XCTUnwrap(params["txid"] as? String, "getActions must carry a txid")
    }

    /// The bug, verbatim: the two spellings of one EVM order hash — what the app
    /// actually sends (`0x…`, lowercase) and what Midgard indexes it under
    /// (UPPER, no prefix) — must produce the SAME query.
    func testAnEvmHashIsNormalizedToMidgardsTxidConvention() throws {
        let asSent = try txid(forHash: "0x10354d6675431a36a62f4ad4fe4c88106fcf39098ddcabfc2b96b1df848f7e73")
        let asIndexed = try txid(forHash: "10354D6675431A36A62F4AD4FE4C88106FCF39098DDCABFC2B96B1DF848F7E73")

        XCTAssertEqual(asSent, asIndexed)
        XCTAssertEqual(asSent, "10354D6675431A36A62F4AD4FE4C88106FCF39098DDCABFC2B96B1DF848F7E73")
        XCTAssertFalse(asSent.hasPrefix("0x"), "the `0x` prefix must be stripped")
    }

    func testAnUppercaseZeroXPrefixIsAlsoStripped() throws {
        XCTAssertEqual(try txid(forHash: "0Xabc123"), "ABC123")
    }

    /// ⚠️ No regression for the native caller. A THORChain hash is already
    /// uppercase hex with no prefix, so normalization is a no-op on it.
    func testANativeThorchainHashIsUnchanged() throws {
        let native = "A1B2C3D4E5F60718293A4B5C6D7E8F90A1B2C3D4E5F60718293A4B5C6D7E8F90"
        XCTAssertEqual(try txid(forHash: native), native)
    }

    /// A leading hex `0` that is NOT a `0x` prefix must be preserved.
    func testALeadingZeroHexDigitIsNotMistakenForAPrefix() throws {
        XCTAssertEqual(try txid(forHash: "0A1B2C"), "0A1B2C")
    }
}
