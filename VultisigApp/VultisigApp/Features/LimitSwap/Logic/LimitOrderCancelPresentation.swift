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

    /// Hero for the initiator's Verify and Done screens, or `nil` when the
    /// transaction is not a cancel (every other function call keeps its existing
    /// presentation).
    ///
    /// ⚠️ **No amount, on either route.** A cancel moves no funds by design: on
    /// the THORChain route it is a memo-only `MsgDeposit` and the amount is
    /// literally zero, and on the L1 route the only thing moving is dust that
    /// exists so Bifrost has something to observe. Neither is a transfer the
    /// user is making, and a hero built around one reports a figure that is an
    /// artifact of reusing the send screen.
    ///
    /// The dust does not stop being disclosed — it is a cost row in the summary
    /// card, beside the network fee, where it reads as what it is. See
    /// `FunctionCallVerifyScreen.cancelLimitOrderRows`.
    static func hero(for transaction: SendTransaction) -> HeroContent? {
        guard let cancel = transaction.limitCancelContext else { return nil }
        return .title(text: title, caption: "\(cancel.sourceAsset) → \(cancel.targetAsset)")
    }

    /// Hero for a CO-SIGNER's screens.
    ///
    /// Keyed on the memo because that is all a co-signing device has: it holds a
    /// `KeysignPayload`, never the initiator's `SendTransaction`. No caption —
    /// the assets are inside the memo in their full THORChain spelling, which is
    /// not what the rest of the app shows an order under, and half-translating
    /// them here would invite a mismatch.
    ///
    /// ⚠️ The co-signer's disclosure of the donated dust does not live here.
    /// It is its own line on the JOIN screen (`KeysignMessageConfirmView`), fed
    /// by `attachedDust(in:)` — which is the screen where a co-signer decides
    /// whether to sign, and therefore the screen where that money has to be
    /// named.
    static func hero(forSignedMemo memo: String?) -> HeroContent? {
        guard isCancelLimitSwapMemo(memo) else { return nil }
        return .title(text: title, caption: nil)
    }

    /// What a co-signer is about to give away, or `nil` when the cancel attaches
    /// nothing (the THORChain route, where zero is the correct and intended
    /// amount).
    static func attachedDust(in payload: KeysignPayload?) -> HeroCoinAmount? {
        guard let payload, isCancelLimitSwapMemo(payload.memo), payload.toAmount > 0 else { return nil }
        return HeroCoinAmount(
            amount: payload.toAmountDecimal.formatForDisplay(),
            ticker: payload.coin.ticker,
            logo: payload.coin.logo
        )
    }

    /// Whether a transaction about to be signed is a limit-order cancel, judged
    /// the way the chain judges it.
    static func isCancel(memo: String?) -> Bool {
        isCancelLimitSwapMemo(memo)
    }

    private static var title: String { "limitSwap.cancel.verify.title".localized }
}
