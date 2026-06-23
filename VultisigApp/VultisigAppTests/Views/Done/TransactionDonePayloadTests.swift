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

import BigInt
import XCTest
@testable import VultisigApp

final class TransactionDonePayloadTests: XCTestCase {

    // MARK: - Swap Done fee-breakdown gate
    //
    // `SwapDoneSummaryCard` offers the "Total fee" expand chevron only when
    // `transaction.hasFeeBreakdown` is true. The chevron renders off
    // `showTotalFees`, but the breakdown rows render off `showFees` / `showGas`
    // — independent flags. When the total is non-zero but both components are
    // suppressed the chevron used to expand an empty box (the reported bug), so
    // the card now falls back to a plain non-tappable total row instead.

    func testHasFeeBreakdownTrueWhenGasPresent() {
        // Non-zero gas drives `showGas`, so the breakdown has a network-fee row
        // to reveal — the chevron is meaningful and should be offered.
        let transaction = makeThorchainTransaction(gas: BigInt(10_000))
        XCTAssertTrue(transaction.showGas)
        XCTAssertTrue(transaction.hasFeeBreakdown)
    }

    func testHasFeeBreakdownFalseWhenComponentsSuppressed() {
        // Zero gas + a zero-fee quote => both `showGas` and `showFees` are
        // false, so expanding would reveal nothing. The gate must be false so
        // the card renders the total as a plain row with no chevron.
        let transaction = makeThorchainTransaction(gas: 0)
        XCTAssertFalse(transaction.showGas)
        XCTAssertFalse(transaction.showFees)
        XCTAssertFalse(transaction.hasFeeBreakdown)
    }

    private func makeThorchainTransaction(gas: BigInt) -> SwapTransaction {
        let rune = makeCoin(.thorChain, ticker: "RUNE", decimals: 8, isNative: true)
        let btc = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true)
        let quote = ThorchainSwapQuote(
            dustThreshold: nil,
            expectedAmountOut: "100000000",
            expiry: 0,
            fees: Fees(affiliate: "0", asset: "RUNE", outbound: "0", total: "0", liquidity: nil, slippageBps: nil, totalBps: nil),
            inboundAddress: "thor-inbound",
            inboundConfirmationBlocks: nil,
            inboundConfirmationSeconds: nil,
            memo: "thor-memo",
            notes: "",
            outboundDelayBlocks: 0,
            outboundDelaySeconds: 0,
            recommendedMinAmountIn: "0",
            slippageBps: nil,
            totalSwapSeconds: nil,
            warning: "",
            router: nil,
            maxStreamingQuantity: nil
        )
        return SwapTransaction(
            fromCoin: rune,
            toCoin: btc,
            fromAmount: 1.0,
            quote: .thorchain(quote),
            gas: gas,
            thorchainFee: 0,
            vultDiscountBps: 0,
            referralDiscountBps: 0,
            feeCoin: rune,
            advancedSettings: .default
        )
    }

    private func makeCoin(_ chain: Chain, ticker: String, decimals: Int, isNative: Bool) -> Coin {
        let asset = CoinMeta.make(chain: chain, ticker: ticker, decimals: decimals, isNativeToken: isNative)
        return Coin(asset: asset, address: "test-address-\(ticker)", hexPublicKey: "")
    }

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
