//
//  LimitOrderCancelPresentationTests.swift
//  VultisigAppTests
//
//  What the signing screens SAY a cancel is.
//
//  Two properties are worth pinning. First, a cancel must not render through the
//  send vocabulary: the THORChain route moves nothing, so the generic header
//  reports "0 RUNE", and the L1 route moves dust that is donated to the pool, so
//  it reports a send of money the user is not sending anywhere. Second — and this
//  is the one that matters — a confirmed cancel TRANSACTION must never be worded
//  as a cancelled ORDER. THORChain accepts a cancel that addresses the wrong
//  ratio bucket, charges for it, and closes nothing.
//

import XCTest
@testable import VultisigApp

@MainActor
final class LimitOrderCancelPresentationTests: XCTestCase {

    // MARK: - Verify

    /// The THORChain route attaches nothing on purpose — anything sent with an
    /// `m=<` is donated to the pool — so there is no amount to show, and showing
    /// the zero would be reporting an artifact of reusing the send screen.
    func testAThorchainCancelGetsATitleHeroWithNoAmount() {
        guard case let .title(text, caption)? = LimitOrderCancelPresentation.hero(for: makeCancelTransaction(amount: "0")) else {
            return XCTFail("expected a title hero for a zero-amount cancel")
        }

        XCTAssertEqual(text, "limitSwap.cancel.verify.title".localized)
        XCTAssertFalse(text.isEmpty)
        XCTAssertEqual(caption, "THOR.RUNE → BTC.BTC")
    }

    /// The L1 route really does move dust, and that dust is unrecoverable, so it
    /// is shown — under a title that says what it is for.
    func testAnL1CancelShowsTheDustItActuallySends() {
        guard case let .send(title, coin)? = LimitOrderCancelPresentation.hero(for: makeCancelTransaction(amount: "2")) else {
            return XCTFail("expected a send hero for a dust-bearing cancel")
        }

        XCTAssertEqual(title, "limitSwap.cancel.verify.title".localized)
        XCTAssertEqual(coin.ticker, "RUNE")
        XCTAssertFalse(coin.amount.isEmpty)
    }

    /// Everything that is not a cancel keeps the presentation it already had.
    func testANonCancelTransactionGetsNoHero() {
        XCTAssertNil(LimitOrderCancelPresentation.hero(for: SendTransaction.empty(coin: makeRune(), vault: .example)))
    }

    // MARK: - The co-signer, which has only the memo

    /// A co-signing device never sees the initiator's `SendTransaction`. The
    /// `m=<` prefix is the discriminator, which is also how THORChain reads it.
    func testACoSignerRecognisesACancelFromItsMemo() {
        let hero = LimitOrderCancelPresentation.hero(
            forSignedMemo: "m=<:100000000THOR.RUNE:15979057441BTC.BTC:0"
        )

        guard case let .title(text, caption)? = hero else {
            return XCTFail("expected a title hero")
        }
        XCTAssertEqual(text, "limitSwap.cancel.verify.title".localized)
        XCTAssertNil(caption)
    }

    /// ⚠️ A PLACEMENT (`=<:`) is a different memo type and must not be swept up:
    /// its own vocabulary talks about the order coming to rest.
    func testAPlacementMemoIsNotTreatedAsACancel() {
        let placement = "=<:BTC.BTC:bc1qdest:544e6/14400/0"

        XCTAssertNil(LimitOrderCancelPresentation.hero(forSignedMemo: placement))
        XCTAssertFalse(LimitOrderCancelPresentation.isCancel(memo: placement))
        XCTAssertNil(LimitOrderCancelPresentation.hero(forSignedMemo: nil))
    }

    // MARK: - The done screen's verb

    /// ⚠️ The whole point. What succeeded is the TRANSACTION. Saying "cancelled"
    /// here would claim an outcome only the queue can report, and would be the
    /// false success this feature exists to prevent.
    func testTheConfirmedCancelVerbDoesNotClaimTheOrderClosed() {
        let verb = TransactionActionVerb.cancelLimitOrder

        XCTAssertEqual(verb.successfulKey, "limitSwap.cancel.done.sent")
        XCTAssertNotEqual(verb.successfulKey.localized, "limitSwap.status.cancelled".localized)
        XCTAssertNotEqual(verb.successfulKey.localized, TransactionActionVerb.send.successfulKey.localized)
    }

    /// And it says so in as many words, on the one screen the user is most
    /// likely to walk away from.
    func testAConfirmedCancelExplainsThatTheOrderIsStillOpen() {
        let detail = TransactionActionVerb.cancelLimitOrder.detailKey(for: .confirmed)

        XCTAssertEqual(detail, "limitSwap.cancel.done.sentDetail")
        XCTAssertFalse((detail ?? "").localized.isEmpty)
    }

    /// The highlighted fragment has to actually occur in the sentence it
    /// highlights — otherwise the accent silently matches nothing.
    func testTheHighlightedFragmentsOccurInTheirSentences() {
        let verb = TransactionActionVerb.cancelLimitOrder

        XCTAssertTrue(
            verb.successfulKey.localized.contains(verb.successfulHighlightKey.localized),
            "success highlight must be a substring of the success sentence"
        )
        XCTAssertTrue(
            verb.failedKey.localized.contains(verb.failedHighlightKey.localized),
            "failure highlight must be a substring of the failure sentence"
        )
    }

    /// A cancel and a placement are opposite claims and must not share copy.
    func testTheCancelVerbIsDistinctFromThePlacementVerb() {
        XCTAssertNotEqual(
            TransactionActionVerb.cancelLimitOrder.successfulKey,
            TransactionActionVerb.limitOrder.successfulKey
        )
        XCTAssertNotEqual(
            TransactionActionVerb.cancelLimitOrder.pendingKey,
            TransactionActionVerb.limitOrder.pendingKey
        )
    }

    // MARK: - Helpers

    private func makeRune() -> Coin {
        let asset = CoinMeta(
            chain: .thorChain,
            ticker: "RUNE",
            logo: "rune",
            decimals: 8,
            priceProviderId: "thorchain",
            contractAddress: "",
            isNativeToken: true
        )
        return Coin(asset: asset, address: "thor1sender", hexPublicKey: "HexPublicKeyExample")
    }

    private func makeCancelTransaction(amount: String) -> SendTransaction {
        let coin = makeRune()
        return SendTransaction(
            coin: coin,
            vault: .example,
            fromAddress: coin.address,
            toAddress: "",
            toAddressLabel: nil,
            amount: amount,
            amountInFiat: "",
            memo: "m=<:100000000THOR.RUNE:15979057441BTC.BTC:0",
            gas: .zero,
            fee: .zero,
            feeMode: .default,
            estimatedGasLimit: nil,
            customGasLimit: nil,
            customByteFee: nil,
            sendMaxAmount: false,
            isStakingOperation: false,
            transactionType: .unspecified,
            memoFunctionDictionary: [:],
            wasmContractPayload: nil,
            feeCoin: coin,
            limitCancelContext: LimitOrderCancelRequest(
                orderId: "order-1",
                inboundTxHash: "ABC123",
                memo: "m=<:100000000THOR.RUNE:15979057441BTC.BTC:0",
                sourceAsset: "THOR.RUNE",
                targetAsset: "BTC.BTC",
                sourceChainRawValue: Chain.thorChain.rawValue,
                duplicateRestingOrderCount: 0
            )
        )
    }
}
