//
//  CosmosAminoTimeoutHeightTests.swift
//  VultisigAppTests
//
//  A dApp's amino sign doc carries a tx-level `timeout_height`. Dropping it
//  signs different bytes than the chain rebuilds, so the broadcast fails.
//  Unset and 0 must behave identically (WalletCore omits the key at 0).
//

@testable import VultisigApp
import XCTest

final class CosmosAminoTimeoutHeightTests: XCTestCase {
    private let fee = CosmosFee(payer: "", granter: "", feePayer: "", amount: [], gas: "200000")

    func testProtoRoundTripKeepsTimeoutHeight() {
        let amino = SignAmino(fee: fee, msgs: [], timeoutHeight: 33_737_015)
        XCTAssertEqual(SignAmino(proto: amino.mapToProtobuff()).timeoutHeight, 33_737_015)
    }

    func testUnsetStaysUnsetOnTheWire() {
        let proto = SignAmino(fee: fee, msgs: []).mapToProtobuff()
        XCTAssertFalse(proto.hasTimeoutHeight)
        XCTAssertNil(SignAmino(proto: proto).timeoutHeight)
    }

    func testZeroIsTreatedAsUnset() throws {
        let zero = SignAmino(fee: fee, msgs: [], timeoutHeight: 0)
        XCTAssertEqual(zero.timeoutHeight ?? 0, 0)
    }
}
