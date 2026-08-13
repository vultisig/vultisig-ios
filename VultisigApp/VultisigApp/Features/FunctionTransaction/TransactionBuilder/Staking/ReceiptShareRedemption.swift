//
//  ReceiptShareRedemption.swift
//  VultisigApp
//

import Foundation

/// Converts a withdrawal amount into the receipt base units a `liquid.unbond`
/// redemption is FUNDED with.
///
/// The sibling of `WithdrawBasisPoints`, for the other kind of unstake this app
/// builds. A fractional-withdrawal memo (`tcy-:<bps>`, `POOL-:<bps>`) names a
/// share of the position and can express nothing finer than a ten-thousandth. A
/// `liquid.unbond` names no figure at all — the wasm execute is empty and the
/// funds attached to it are the instruction, an ABSOLUTE count of receipt units
/// (`x/staking-x/brune`, `x/staking-x/ruji`). An absolute count has no coarse
/// step to work around: the smallest thing it can express is one base unit,
/// 0.00000001 of a share.
///
/// So the ten-thousandths are the wrong ceiling here, not the right one. What
/// these two positions were actually doing was worse than either: they reached
/// the share count through `Int(percentageSelected ?? percentageFromAmount)`,
/// which floors the fraction to a whole percent and makes one step a whole 1% of
/// the position — ~20 tokens on the 2002.74 position the defect was reported
/// against. Converting the typed amount straight into base units removes the step
/// entirely rather than making it 100× smaller.
///
/// ⚠️ **The amount and the receipt are not always in the same units.** The two
/// callers differ, and the difference is why this takes a `positionValue` instead
/// of assuming one:
///
/// - **bRUNE/ybRUNE** — the staked card renders the ybRUNE receipt balance
///   directly, so the typed amount already IS a receipt figure and the conversion
///   comes out exact.
/// - **RUJI/sRUJI** — the compounded card renders the RUJI the receipt is worth,
///   so the typed amount is priced in RUJI and the share count follows from the
///   ratio between the two balances the sheet was opened with.
///
/// Passing both figures makes the conversion correct either way, and it stays
/// bounded by the shares actually held rather than by an invariant asserted
/// somewhere else.
enum ReceiptShareRedemption {

    /// `value` truncated to whole base units.
    ///
    /// A `CosmosCoin.amount` is an integer string, and a fractional one is
    /// malformed. Truncating rather than rounding is the same call
    /// `WithdrawBasisPoints` makes and for the same reason: **a redemption never
    /// spends more of the position than was asked for**, and rounding up could
    /// also exceed the shares actually held, which fails on-chain.
    static func wholeUnits(_ value: Decimal) -> Decimal {
        guard value > 0 else { return 0 }
        var raw = value
        var floored = Decimal()
        NSDecimalRound(&floored, &raw, 0, .down)
        return floored
    }

    /// The whole receipt base units to redeem for `amount` of a position worth
    /// `positionValue`, out of the `receiptBaseUnits` held. `0` when there is
    /// nothing to redeem, which is never a valid instruction — a `liquid.unbond`
    /// funded with nothing pays a fee to withdraw nothing, so the callers refuse
    /// to build one.
    ///
    /// ⚠️ **`closingPosition` pins the whole balance rather than deriving it.**
    /// The amount field renders a rounded figure, so deriving a full exit from it
    /// could leave a sliver of shares behind and keep a position open the user
    /// asked to close. Same reason `UnstakeTransactionViewModel.withdrawBasisPoints`
    /// pins 10000 for MAX.
    ///
    /// ⚠️ **A partial withdrawal can never close the position.** Truncation only
    /// moves the result down, and the result only reaches the held balance when
    /// `amount` reaches `positionValue` — which is a full exit however it was
    /// typed. The clamp is what stops an over-balance figure asking for more
    /// shares than exist; rejecting that figure is `AmountBalanceValidator`'s job,
    /// and it has to let the value through to report it.
    static func baseUnits(
        forAmount amount: Decimal,
        positionValue: Decimal,
        receiptBaseUnits: Decimal,
        closingPosition: Bool
    ) -> Decimal {
        let held = wholeUnits(receiptBaseUnits)
        guard held >= 1 else { return 0 }
        guard !closingPosition else { return held }
        guard positionValue > 0, amount > 0 else { return 0 }

        // Multiplied BEFORE it is divided. Taking the fraction first
        // (`amount / positionValue`) rounds it to the mantissa's 38 digits and
        // then scales that error up by the share count, which can land a whole
        // base unit short of an exact figure. This order divides once, at the
        // end, so an amount that is an exact share of the position converts
        // exactly.
        let redeemed = wholeUnits((held * amount) / positionValue)
        return min(redeemed, held)
    }
}
