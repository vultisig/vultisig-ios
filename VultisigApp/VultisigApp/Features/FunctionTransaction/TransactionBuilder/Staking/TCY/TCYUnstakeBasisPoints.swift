//
//  TCYUnstakeBasisPoints.swift
//  VultisigApp
//

import Foundation

/// Converts a TCY withdrawal amount into the basis points the `tcy-:<bps>` memo
/// actually carries.
///
/// ⚠️ **The memo names a fraction of the position, never an amount.** THORChain's
/// `tcy-` handler reads ten-thousandths of whatever is staked at execution time,
/// so an arbitrary decimal amount is not representable and no amount of app-side
/// care can make one withdraw exactly. (Contrast `RUJIUnstakeTransactionBuilder`,
/// whose `withdraw:<asset>:<raw>` memo *does* carry an absolute amount and is
/// therefore exact — the difference is the protocol, not this code.)
///
/// What was representable and was being thrown away is the resolution. The amount
/// used to reach the memo through a whole percentage — `Int(50.0679) * 100` — which
/// spends 100 of the 10 000 steps the memo can address. On a 2002.74 TCY position
/// one of those coarse steps is 20.03 TCY, and that is the reported bug: a request
/// for 1002.73 floored to 50% and paid out 1001.37.
///
/// Converting straight to basis points and rounding to the nearest one leaves an
/// error of at most half a basis point — 0.005% of the position, about 0.10 TCY on
/// that same position — which is as close as the memo can get to any given amount.
/// Because the result can no longer land on the user's exact figure, the screens
/// around signing quote the quantised amount rather than the typed one; see
/// `TCYUnstakePresentation`.
enum TCYUnstakeBasisPoints {

    /// A full exit. Also the clamp ceiling — a memo can never ask for more of the
    /// position than all of it.
    static let max = 10_000

    /// The smallest fraction the memo can express. Anything under one basis point
    /// of the position rounds to `tcy-:0`, which asks for nothing.
    static let min = 1

    /// Basis points of `available` that `amount` comes to, rounded to nearest and
    /// clamped to `1...10000`, or `0` when the amount is too small to survive the
    /// rounding (or there is nothing staked). A `0` is never a valid memo — it is
    /// the signal for `TCYUnstakeAmountValidator` to reject the amount.
    static func value(forAmount amount: Decimal, available: Decimal) -> Int {
        guard available > 0, amount > 0 else { return 0 }

        var raw = (amount / available) * Decimal(max)
        var rounded = Decimal()
        // `.plain` rounds half away from zero. Nearest is what tracks the user's
        // intent most closely; the clamp below is what stops it exceeding the
        // position, so rounding up can never over-withdraw.
        NSDecimalRound(&rounded, &raw, 0, .plain)

        let bps = NSDecimalNumber(decimal: rounded).intValue
        guard bps >= min else { return 0 }
        return Swift.min(bps, max)
    }

    /// One whole basis point of `available`, rounded UP to 4 decimals — the floor
    /// `TCYUnstakeAmountValidator` enforces, and the figure its message quotes.
    ///
    /// A full basis point rather than the half that would technically survive
    /// rounding: half a basis point *does* round up to one, but then the user
    /// receives twice what they asked for. Refusing the amount and naming a
    /// figure that behaves is better than silently doubling it. Rounding the
    /// quoted figure up keeps the message honest — retyping exactly what it says
    /// passes.
    static func minimumAmount(forAvailable available: Decimal) -> Decimal {
        guard available > 0 else { return 0 }
        var raw = available / Decimal(max)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &raw, 4, .up)
        return rounded
    }
}
