//
//  LimitOrderCancelPresentation.swift
//  VultisigApp
//
//  How a limit-order CANCEL is presented on the screens that surround signing:
//  Verify, the co-signer's keysign summary, and the done screen.
//
//  Without it a cancel renders through the generic send vocabulary — "You're
//  sending 0 RUNE" on the THORChain route, and "You're sending 2 DOGE" on the L1
//  one, where the two DOGE are dust that gets donated to the pool. Neither
//  sentence is what the user is doing.
//
//  ⚠️ **App-side on purpose, and it must stay that way.**
//  `TransactionBuilder.transactionType` is `VSTransactionType`, generated from
//  the `commondata` protobuf submodule shared with vultisig-android,
//  vultisig-windows and the Go backends. A cancel needs no new wire value: it is
//  an ordinary THORChain `MsgDeposit` (or an L1 dust send) whose entire meaning
//  lives in its `m=<` memo, and the signer already emits the correct bytes under
//  `.unspecified`. Adding a case there would ripple through four codebases to
//  change how one screen reads a sentence.
//
//  So the verb is derived from the MEMO — the same thing THORChain itself reads
//  to decide what the transaction is. That is also what makes the co-signer
//  branch possible: a co-signing device never sees the initiator's
//  `SendTransaction`, only the payload it is asked to sign.
//

import Foundation

enum LimitOrderCancelPresentation {

    /// Hero for the initiator's Verify screen, or `nil` when the transaction is
    /// not a cancel (every other function call keeps its existing presentation).
    static func hero(for transaction: SendTransaction) -> HeroContent? {
        guard let cancel = transaction.limitCancelContext else { return nil }
        let caption = "\(cancel.sourceAsset) → \(cancel.targetAsset)"
        guard transaction.amountDecimal > 0 else {
            // THORChain route: the cancel attaches nothing, on purpose —
            // anything sent with an `m=<` is donated to the pool. A hero built
            // around "0 RUNE" would be reporting an amount that exists only as
            // an artifact of reusing the send screen.
            return .title(text: title, caption: caption)
        }
        // L1 route: the cancel genuinely moves dust, and that dust is
        // unrecoverable, so it is shown rather than hidden behind a title. The
        // exact figure and its fate are spelled out in the disclosures below it.
        return .send(
            title: title,
            coin: HeroCoinAmount(
                amount: transaction.amountDecimal.formatForDisplay(),
                ticker: transaction.coin.ticker,
                logo: transaction.coin.logo
            )
        )
    }

    /// Hero for a CO-SIGNER's screens.
    ///
    /// Keyed on the memo because that is all a co-signing device has: it holds a
    /// `KeysignPayload`, never the initiator's `SendTransaction`. No caption —
    /// the assets are inside the memo in their full THORChain spelling, which is
    /// not what the rest of the app shows an order under, and half-translating
    /// them here would invite a mismatch.
    ///
    /// ⚠️ `attached` must be passed whenever the payload actually moves value.
    /// A co-signer is signing too, and on the L1 route what moves is dust
    /// THORChain donates to the pool with no refund path — up to two whole DOGE.
    /// Retitling the hero without carrying the amount would hide that money on
    /// the one screen where the co-signer decides whether to join.
    static func hero(forSignedMemo memo: String?, attached: HeroCoinAmount? = nil) -> HeroContent? {
        guard isModifyLimitSwapMemo(memo) else { return nil }
        guard let attached else { return .title(text: title, caption: nil) }
        return .send(title: title, coin: attached)
    }

    /// What a co-signer is about to give away, or `nil` when the cancel attaches
    /// nothing (the THORChain route, where zero is the correct and intended
    /// amount).
    static func attachedDust(in payload: KeysignPayload?) -> HeroCoinAmount? {
        guard let payload, isModifyLimitSwapMemo(payload.memo), payload.toAmount > 0 else { return nil }
        return HeroCoinAmount(
            amount: payload.toAmountDecimal.formatForDisplay(),
            ticker: payload.coin.ticker,
            logo: payload.coin.logo
        )
    }

    /// Whether a transaction about to be signed is a limit-order cancel, judged
    /// the way the chain judges it.
    static func isCancel(memo: String?) -> Bool {
        isModifyLimitSwapMemo(memo)
    }

    private static var title: String { "limitSwap.cancel.verify.title".localized }
}
