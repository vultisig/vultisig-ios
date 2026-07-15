//
//  LimitSwapRecipientVerifierTests.swift
//  VultisigAppTests
//
//  The limit path builds its keysign payload via `buildLimitSwapKeysignPayload`
//  directly, bypassing `DefaultSwapInteractor.buildSwapKeysignPayload` and the
//  `SwapRecipientVerifier.verify` gate it runs. `SwapVerifyViewModel` now runs
//  that same gate on the limit transaction before building — these tests pin the
//  transaction-level behavior it relies on.
//

@testable import VultisigApp
import BigInt
import XCTest

@MainActor
final class LimitSwapRecipientVerifierTests: XCTestCase {

    private var storeToken: TestContextToken!

    override func setUp() async throws {
        try await super.setUp()
        storeToken = try TestStore.installInMemoryContainer()
    }

    override func tearDown() async throws {
        TestStore.restore(storeToken)
        storeToken = nil
        try await super.tearDown()
    }

    private func makeLimitTransaction(externalRecipient: String?) -> SwapTransaction {
        let from = Coin(
            asset: CoinMeta.make(chain: .bitcoin, ticker: "BTC", decimals: 8),
            address: "bc1qsourceaddress0000000000000000000000000",
            hexPublicKey: "btc-pubkey"
        )
        let to = Coin(
            asset: CoinMeta.make(chain: .ethereum, ticker: "ETH", decimals: 18),
            address: "0xdestaddress000000000000000000000000000000",
            hexPublicKey: "eth-pubkey"
        )
        let record = LimitOrderRecord(
            inboundTxHash: "",
            sourceAsset: "BTC.BTC",
            sourceAmount: "100000000",
            sourceDecimals: 8,
            targetAsset: "ETH.ETH",
            destAddress: "0xdestaddress000000000000000000000000000000",
            targetPrice: 16,
            expiryBlocks: 14_400,
            memo: "=<:ETH.ETH:0xdestaddress000000000000000000000000000000:16e8/14400/0:vi:0",
            expiryHours: 24
        )
        var settings = SwapAdvancedSettings.default
        settings.externalRecipient = externalRecipient
        return SwapTransaction(
            fromCoin: from,
            toCoin: to,
            fromAmount: 1,
            kind: .limit(record),
            gas: 0,
            gasLimit: 0,
            thorchainFee: 0,
            vultDiscountBps: 0,
            referralDiscountBps: 0,
            feeCoin: from,
            advancedSettings: settings
        )
    }

    func testLimitOrderWithoutExternalRecipientPassesVerification() {
        // The user's own address is the destination — nothing external to verify.
        let tx = makeLimitTransaction(externalRecipient: nil)
        XCTAssertFalse(tx.hasExternalRecipient)
        XCTAssertNoThrow(try SwapRecipientVerifier.verify(transaction: tx))
    }

    func testLimitOrderWithExternalRecipientFailsClosed() {
        // A limit order carries no market quote to verify an output target
        // against; if a recipient is ever attached, verification must fail closed
        // rather than sign a blind, unverifiable destination.
        let tx = makeLimitTransaction(externalRecipient: "0xexternalrecipient00000000000000000000000")
        XCTAssertThrowsError(try SwapRecipientVerifier.verify(transaction: tx)) {
            XCTAssertEqual($0 as? SwapError, .recipientVerificationFailed)
        }
    }
}
