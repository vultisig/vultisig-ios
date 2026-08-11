//
//  WithdrawBasisPoints.swift
//  VultisigApp
//

import Foundation

/// Converts a withdrawal amount into the basis points a *fractional* withdrawal
/// memo carries.
///
/// ⚠️ **Such a memo names a fraction of the position, never an amount.** THORChain's
/// `tcy-:<bps>` handler and MAYAChain's `POOL-:<bps>` one both read ten-thousandths
/// of whatever is staked at execution time, so an arbitrary decimal amount is not
/// representable and no amount of app-side care can make one withdraw exactly.
/// (Contrast `RUJIUnstakeTransactionBuilder`, whose `withdraw:<asset>:<raw>` memo
/// *does* carry an absolute amount and is therefore exact — the difference is the
/// protocol, not this code.)
///
/// What was representable and was being thrown away is the resolution. The amount
/// used to reach the memo through a whole percentage — `Int(50.0679) * 100` — which
/// spends 100 of the 10 000 steps the memo can address. Worked through on the
/// staked-TCY position the defect was reported against: 2002.74 TCY, where one of
/// those coarse steps is 20.03 TCY, so a request for 1002.73 floored to 50% and
/// paid out 1001.37. The same arithmetic applies to any position and any of these
/// memos — the ten-thousandths are a property of the convention, not of TCY.
///
/// Converting straight to basis points and rounding DOWN (see `value(forAmount:available:)`
/// for why down) leaves at most one basis point behind — 0.01% of the position,
/// about 0.20 TCY on that same position — and never takes more than was asked for.
/// Because the result can no longer land on the user's exact figure, the screens
/// around signing quote the quantised amount rather than the typed one; the TCY
/// instance of that is `TCYUnstakePresentation`.
enum WithdrawBasisPoints {

    /// A full exit. Also the clamp ceiling — a memo can never ask for more of the
    /// position than all of it.
    static let max = 10_000

    /// The smallest fraction the memo can express. Anything under one basis point
    /// of the position rounds to a `:0` memo, which asks for nothing.
    static let min = 1

    /// Basis points of `available` that `amount` comes to, rounded DOWN and
    /// clamped to `1...10000`, or `0` when the amount is smaller than a single
    /// basis point (or there is nothing staked). A `0` is never a valid memo — it
    /// is the signal for `WithdrawMinimumAmountValidator` to reject the amount.
    ///
    /// ⚠️ **Down, not to nearest.** Rounding to nearest tracks the typed figure
    /// more closely on average, but it can round *up*, and up has a cliff at the
    /// top: anything from 99.995% of the position upwards reaches 10000 and
    /// closes the position outright. Someone asking to withdraw 2002.64 of 2002.74
    /// is asking to keep 0.10 TCY, and taking the last of it is not a rounding
    /// difference — it is a different outcome. Rounding down makes the invariant
    /// simple and checkable: **a withdrawal never takes more of the position than
    /// was asked for, and only an explicit full exit reaches 10000.**
    ///
    /// The cost is up to one whole basis point left behind (0.01% of the
    /// position, ~0.20 TCY on that same position) instead of half of one. Still
    /// 100× finer than the whole-percent truncation this replaces, and the
    /// remainder stays staked rather than being taken. `RUJILiquidUnbondTransactionBuilder`
    /// rounds down for the same reason.
    static func value(forAmount amount: Decimal, available: Decimal) -> Int {
        guard available > 0, amount > 0 else { return 0 }

        var raw = (amount / available) * Decimal(max)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &raw, 0, .down)

        let bps = NSDecimalNumber(decimal: rounded).intValue
        guard bps >= min else { return 0 }
        return Swift.min(bps, max)
    }

    /// Exactly one basis point of `available` — the threshold below which
    /// `value(forAmount:available:)` returns 0 and there is nothing to ask the
    /// chain for.
    ///
    /// ⚠️ Deliberately NOT rounded. Rounding the threshold up to a display
    /// precision makes small positions unwithdrawable: a 0.00005 position would
    /// be compared against a 0.0001 minimum and could never be closed, not even
    /// at MAX.
    static func minimumAmount(forAvailable available: Decimal) -> Decimal {
        guard available > 0 else { return 0 }
        return available / Decimal(max)
    }

    /// The same threshold rounded UP to `digits`, for the figure the error
    /// message quotes. Up, so that retyping exactly what the message says
    /// passes the comparison against the exact threshold above.
    static func quotedMinimum(forAvailable available: Decimal, digits: Int) -> Decimal {
        var raw = minimumAmount(forAvailable: available)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &raw, digits, .up)
        return rounded
    }
}
