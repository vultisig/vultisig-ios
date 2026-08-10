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
                // `formatToDecimal`, not `formatForDisplay`: the latter
                // abbreviates anything over a million ("1.2M TCY" is not a figure
                // anyone can check against what they asked for) and, below a
                // million, ignores its own `maxDecimals` and renders 8 places.
                // Four matches the precision of the field the amount was typed
                // into, so the two read as the same number.
                amount: amount.formatToDecimal(digits: 4),
                ticker: transaction.coin.ticker,
                logo: transaction.coin.logo
            )
        )
    }
}
