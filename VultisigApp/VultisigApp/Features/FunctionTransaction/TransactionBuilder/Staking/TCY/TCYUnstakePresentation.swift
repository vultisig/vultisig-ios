//
//  TCYUnstakePresentation.swift
//  VultisigApp
//
//  How a staked-TCY withdrawal is presented on the screen where it is approved.
//
//  Without it the withdrawal renders through the generic send vocabulary and the
//  verify screen reads **"You're sending 0 TCY"** over a withdrawal of a thousand
//  of them. Both halves of that sentence are wrong: nothing is being *sent* — the
//  position is being drawn down — and the zero is the transaction's own `amount`,
//  which really is zero, because a THORChain staking withdrawal is a memo-only
//  `MsgDeposit` whose entire instruction is the memo `tcy-:<bps>`.
//
//  Same shape, and the same escape hatch, as `LimitOrderCancelPresentation`, which
//  fixed the identical "You're sending 0 RUNE" on limit-order cancels.
//

import Foundation

enum TCYUnstakePresentation {

    /// Hero for the initiator's Verify screen, or `nil` for anything that is not a
    /// staked-TCY withdrawal (every other function call keeps its existing
    /// presentation).
    ///
    /// The figure comes from `withdrawDisplayAmount`, carried down from the
    /// builder, rather than being re-derived here from the memo and a balance.
    /// Re-deriving would need `bps × staked position`, and the only position this
    /// screen can see is `coin.stakedBalanceDecimal` — which matches the balance
    /// the sheet was showing *only because* the TCY card happens to pass no
    /// explicit `availableToUnstake`. That is a property of the current wiring, not
    /// a guarantee (the Maya CACAO card passes one), and a hero that silently
    /// disagreed with the form about how much is being withdrawn would be a new
    /// version of the bug this fixes.
    static func hero(for transaction: SendTransaction) -> HeroContent? {
        guard let amount = transaction.withdrawDisplayAmount else { return nil }
        return .send(
            title: "tcyUnstakeVerifyTitle".localized,
            coin: HeroCoinAmount(
                // Rendered at the ASSET'S OWN precision, and that number is
                // derived rather than picked for looking generous.
                //
                // `formatToDecimal` truncates (`roundingMode = .down`), and the
                // chain settles in whole base units — THORChain computes
                // `stakedBaseUnits × bps / 10000` in integer maths and drops the
                // remainder. Truncating the exact product at `coin.decimals` is
                // therefore not an approximation of the payout, it *is* the
                // payout: for a 2002.74 position at 5006 bps both come to
                // 1002.571644 exactly.
                //
                // ⚠️ Four decimals — the precision of the amount FIELD — was
                // wrong here, and wrong in the way this whole screen exists to
                // prevent. It quietly understated that same withdrawal by
                // 0.000044 TCY, and rendered a dust position's full exit as
                // "0.0001" or, below 0.00005, as a flat "0". The field's
                // precision is a property of the field; what the screen has to
                // state is what the chain will pay.
                //
                // Not `formatForDisplay`: it abbreviates past a million ("1.2M
                // TCY" is not a figure anyone can check against what they asked
                // for) and, below a million, ignores its own `maxDecimals`.
                amount: amount.formatToDecimal(digits: transaction.coin.decimals),
                ticker: transaction.coin.ticker,
                logo: transaction.coin.logo
            )
        )
    }
}
