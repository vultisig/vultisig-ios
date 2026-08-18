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
///
/// ⚠️ **What bounds the precision here is the INPUT, not this arithmetic.** The
/// typed figure reaches these builders through `String.toDecimal()`, which parses
/// with `NumberFormatter` and therefore round-trips through a `Double` — so the
/// `Decimal` that arrives can already differ from what was typed in the 16th
/// significant digit. `Decimal`'s own 38-digit multiply and divide below can
/// likewise land one base unit off an exact quotient on a position large enough
/// to need twenty digits.
///
/// Both are real and neither is worth exact integer arithmetic here: the second
/// is a base unit, the first is thousands of times larger on the same position,
/// and no amount of care downstream recovers a figure that was already perturbed
/// upstream. Whichever way that error falls, the result is still truncated and
/// still clamped to the shares held, so the outcome stays within one base unit of
/// the request and can never exceed the position. Tightening the conversion while
/// the amount arrives via `Double` would be precision theatre; the input is where
/// it would have to start.
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
    /// ⚠️ **But the flag alone is not evidence of a full exit**, which is why the
    /// amount has to agree with it. The flag is set from a `Double` percentage
    /// (`AmountPercentageBinding.percentage`), and on a large position a typed
    /// amount a hair under the balance derives exactly `100` — the same value the
    /// field already held, so SwiftUI emits no change, `onPercentage` never runs,
    /// and the flag stays true over an amount that was meant to leave something
    /// staked. Trusting it by itself would close that position.
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
        guard held >= 1, positionValue > 0, amount > 0 else { return 0 }
        if closingPosition, isWholePosition(amount: amount, positionValue: positionValue) {
            return held
        }

        // Multiplied BEFORE it is divided. Taking the fraction first
        // (`amount / positionValue`) rounds it to the mantissa's 38 digits and
        // then scales that error up by the share count, which can land a whole
        // base unit short of an exact figure. This order divides once, at the
        // end, so an amount that is an exact share of the position converts
        // exactly.
        let redeemed = wholeUnits((held * amount) / positionValue)
        return min(redeemed, held)
    }

    /// Whether `amount` is the whole position **as the amount field is able to
    /// state it** — the balance itself, or the figure a MAX selection prefills,
    /// which is that balance truncated to `AmountPercentageBinding.displayedDecimals`.
    ///
    /// The truncated form has to count, or a MAX exit on a position with more
    /// decimals than the field renders would be read as a partial and leave a
    /// sliver staked. Nothing BETWEEN the two counts, which is what makes this a
    /// real check rather than a tolerance: a figure the user typed with more
    /// precision than MAX would have written is a figure MAX did not write.
    ///
    /// ⚠️ **The one case it cannot separate** is a user typing, by hand, exactly
    /// what MAX would have prefilled on a position carrying more decimals than
    /// the field shows. That closes the position, taking up to one display step
    /// more than was asked — bounded, invisible at the precision the screen
    /// renders, and unavoidable from the amount alone. Separating them needs the
    /// field to report that the amount was typed rather than derived, which
    /// `AmountPercentageSync.amountIsUserTyped` already knows and does not
    /// currently surface to the view model.
    static func isWholePosition(amount: Decimal, positionValue: Decimal) -> Bool {
        guard positionValue > 0 else { return false }
        if amount >= positionValue { return true }

        var raw = positionValue
        var prefilled = Decimal()
        NSDecimalRound(&prefilled, &raw, AmountPercentageBinding.displayedDecimals, .down)
        return amount == prefilled
    }
}
