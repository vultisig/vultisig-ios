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

import BigInt
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

    /// ⚠️ The L1 route gets the same title hero, with no amount either.
    ///
    /// The dust it moves is not a transfer the user is making — it exists so
    /// Bifrost has an inbound to observe — and a hero built around it reads as
    /// "you are sending 2 DOGE". It stays disclosed with its exact figure as a
    /// cost row beside the network fee, which is what it is.
    func testAnL1CancelAlsoGetsATitleHeroRatherThanASendOfItsDust() {
        guard case let .title(text, caption)? = LimitOrderCancelPresentation.hero(for: makeCancelTransaction(amount: "2")) else {
            return XCTFail("expected a title hero for a dust-bearing cancel too")
        }

        XCTAssertEqual(text, "limitSwap.cancel.verify.title".localized)
        XCTAssertEqual(caption, "THOR.RUNE → BTC.BTC")
    }

    /// Everything that is not a cancel keeps the presentation it already had.
    func testANonCancelTransactionGetsNoHero() {
        XCTAssertNil(LimitOrderCancelPresentation.hero(for: SendTransaction.empty(coin: makeRune(), vault: .example)))
    }

    // MARK: - The co-signer, which has only the memo

    /// A co-signing device never sees the initiator's `SendTransaction`. The
    /// `m=<` prefix is the discriminator, which is also how THORChain reads it.
    /// The caption names the order's pair, parsed from the memo's own coin legs
    /// (leading amount digits stripped), matching the initiator's raw-spelling
    /// `SRC → TGT` caption.
    func testACoSignerRecognisesACancelFromItsMemo() {
        let hero = LimitOrderCancelPresentation.hero(
            forSignedMemo: "m=<:100000000THOR.RUNE:15979057441BTC.BTC:0"
        )

        guard case let .title(text, caption)? = hero else {
            return XCTFail("expected a title hero")
        }
        XCTAssertEqual(text, "limitSwap.cancel.verify.title".localized)
        XCTAssertEqual(caption, "THOR.RUNE → BTC.BTC")
    }

    /// The pair caption uses each leg's raw THORChain spelling — a secured-asset
    /// source keeps its lower-case denom, exactly as it rides in the memo.
    func testTheCancelCaptionUsesTheMemosRawAssetSpelling() {
        guard case let .title(_, caption)? = LimitOrderCancelPresentation.hero(
            forSignedMemo: "m=<:200000000DOGE.DOGE:15979057441BTC.BTC:0"
        ) else {
            return XCTFail("expected a title hero")
        }
        XCTAssertEqual(caption, "DOGE.DOGE → BTC.BTC")
    }

    /// ⚠️ A co-signer is signing too, and on the L1 route what moves is dust
    /// THORChain donates to the pool with no refund path — up to two whole DOGE.
    /// That money must still be named on the screen where the co-signer decides
    /// whether to join; it is `attachedDust` that names it, on its own line,
    /// rather than the hero.
    func testTheDustACoSignerGivesAwayIsStillResolvable() {
        let dust = LimitOrderCancelPresentation.attachedDust(
            in: makeCancelPayload(memo: "m=<:100000000DOGE.DOGE:15979057441BTC.BTC:0", toAmount: 200_000_000)
        )

        XCTAssertNotNil(dust)
        XCTAssertFalse(dust?.amount.isEmpty ?? true)
    }

    /// The THORChain route attaches nothing, and zero is the correct amount
    /// there — so there is nothing to disclose.
    func testAThorchainCancelHasNoDustToDisclose() {
        let dust = LimitOrderCancelPresentation.attachedDust(
            in: makeCancelPayload(memo: "m=<:100000000THOR.RUNE:15979057441BTC.BTC:0", toAmount: 0)
        )

        XCTAssertNil(dust)
    }

    /// ⚠️ A PLACEMENT (`=<:`) is a different memo type and must not be swept up:
    /// its own vocabulary talks about the order coming to rest.
    func testAPlacementMemoIsNotTreatedAsACancel() {
        let placement = "=<:BTC.BTC:bc1qdest:544e6/14400/0"

        XCTAssertNil(LimitOrderCancelPresentation.hero(forSignedMemo: placement))
        XCTAssertFalse(LimitOrderCancelPresentation.isCancel(memo: placement))
        XCTAssertNil(LimitOrderCancelPresentation.hero(forSignedMemo: nil))
    }

    /// ⚠️ And a RE-TARGET is not a cancel either, even though it shares the
    /// `m=<` prefix. THORNode reads the final field: zero closes the order,
    /// anything else moves it. Calling that "You're cancelling a limit order"
    /// would describe the opposite of what the user asked for.
    func testARetargetMemoIsNotTreatedAsACancel() {
        let retarget = "m=<:100000000THOR.RUNE:15979057441BTC.BTC:16000000000"

        XCTAssertNil(LimitOrderCancelPresentation.hero(forSignedMemo: retarget))
        XCTAssertFalse(LimitOrderCancelPresentation.isCancel(memo: retarget))
        XCTAssertNil(
            LimitOrderCancelPresentation.attachedDust(in: makeCancelPayload(memo: retarget, toAmount: 200_000_000))
        )
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

    private func makeCancelPayload(memo: String, toAmount: BigInt) -> KeysignPayload {
        KeysignPayload(
            coin: makeRune(),
            toAddress: "thor1inbound",
            toAmount: toAmount,
            chainSpecific: .THORChain(
                accountNumber: 1,
                sequence: 1,
                fee: 0,
                isDeposit: true,
                transactionType: 0
            ),
            utxos: [],
            memo: memo,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "pub",
            vaultLocalPartyID: "party",
            libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            skipBroadcast: false,
            signData: nil
        )
    }
}
