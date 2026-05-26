//
//  TransactionDonePayloadTests.swift
//  VultisigAppTests
//
//  Constructor pins for `TransactionDonePayload`. Each flow
//  (Send / Swap / QBTC claim / cosigner) builds one of these and hands
//  it to `DoneScreen`; the tests below lock the shape so a refactor
//  doesn't silently drop a field. The value-type rendering is
//  exercised end-to-end by the build / XCUITest layers — what we
//  pin here is data integrity.
//

import XCTest
@testable import VultisigApp

final class TransactionDonePayloadTests: XCTestCase {

    func testSendDefaultsVerbToSend() {
        // Default-verb behaviour preserves the pre-refactor Send /
        // cosigner-Send caller contract — adding `.claim` to the
        // payload struct must not flip these flows to claim copy.
        let payload = TransactionDonePayload(
            coin: .example,
            amountCrypto: "1.5 ETH",
            amountFiat: "5000",
            hash: "0xdeadbeef",
            explorerLink: "https://etherscan.io/tx/0xdeadbeef",
            memo: "",
            isSend: true,
            fromAddress: "0xfrom",
            toAddress: "0xto",
            fee: FeeDisplay(crypto: "0.001 ETH", fiat: "$3.00"),
            keysignPayload: nil,
            pubKeyECDSA: "vault-pk"
        )
        XCTAssertEqual(payload.verb, .send)
        XCTAssertNil(payload.hero)
        XCTAssertNil(payload.toAlias)
        XCTAssertNil(payload.dappMetadata)
    }

    func testClaimVerbCarriesThrough() {
        // QBTC claim builds the same payload but pins `verb: .claim` so
        // the status header swaps "Transaction" copy for "Claim" copy.
        let payload = TransactionDonePayload(
            coin: .example,
            amountCrypto: "1.0 qBTC",
            amountFiat: "",
            hash: "0xqbtchash",
            explorerLink: "https://qbtc.example/tx/0xqbtchash",
            memo: "",
            isSend: true,
            fromAddress: "btc-addr",
            toAddress: "qbtc-addr",
            fee: FeeDisplay(crypto: "", fiat: ""),
            keysignPayload: nil,
            pubKeyECDSA: "vault-pk",
            verb: .claim
        )
        XCTAssertEqual(payload.verb, .claim)
        XCTAssertEqual(payload.verb.broadcastedKey, "claimBroadcasted")
        XCTAssertEqual(payload.verb.successfulKey, "claimSuccessful")
    }

    func testSwapPayloadCarriesNilKeysignPayload() {
        // Initiator swap doesn't propagate `KeysignPayload` to the
        // unified payload — the from/to/fee detail lives in the
        // `SwapDoneSummaryCard` token slot, not the secondary detail
        // route. Pinned so a future "share the secondary view" idea
        // doesn't silently leak the keysign payload into Swap.
        let payload = TransactionDonePayload(
            coin: .example,
            amountCrypto: "1.5 ETH",
            amountFiat: "5000",
            hash: "0xswap",
            explorerLink: "https://etherscan.io/tx/0xswap",
            memo: "",
            isSend: false,
            fromAddress: "0xfrom",
            toAddress: "0xto",
            fee: FeeDisplay(crypto: "0.001 ETH", fiat: ""),
            keysignPayload: nil,
            pubKeyECDSA: "vault-pk"
        )
        XCTAssertNil(payload.keysignPayload)
        XCTAssertFalse(payload.isSend)
    }

    func testHashableForRouteUse() {
        // `SendRoute.transactionDetails(input: TransactionDonePayload)`
        // requires Hashable. Two payloads with the same content must
        // hash identically — otherwise SwiftUI's NavigationStack
        // diffing breaks on the secondary-detail route.
        let a = TransactionDonePayload(
            coin: .example,
            amountCrypto: "1.5 ETH",
            amountFiat: "5000",
            hash: "0xsame",
            explorerLink: "https://etherscan.io/tx/0xsame",
            memo: "",
            isSend: true,
            fromAddress: "0xfrom",
            toAddress: "0xto",
            fee: FeeDisplay(crypto: "0.001 ETH", fiat: "$3"),
            keysignPayload: nil,
            pubKeyECDSA: "vault-pk"
        )
        let b = a
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
    }
}
