//
//  PercentageAmount.swift
//  VultisigApp
//

import Foundation

/// The conversion, both ways, between a token amount and the 0–100 percentage of
/// a balance that a slider or percentage button shows for it.
///
/// It lives outside the view on purpose. `AmountTextField` owns this binding, but
/// it is a SwiftUI view and this repo carries no view-inspection harness — so the
/// arithmetic deciding what a withdrawal slider claims about the user's money
/// would otherwise be unreachable from a test. It is also the formula the unstake
/// view model falls back to when no percentage was chosen, and one shared
/// definition is what keeps the figure the slider shows and the figure the
/// transaction is built from from drifting apart.
enum PercentageAmount {

    /// The percentage of `available` that `amount` comes to, clamped to 0…100,
    /// or `nil` when there is no balance to take a percentage of.
    ///
    /// The clamp is load-bearing: the amount field accepts whatever is being
    /// typed, including a figure above the balance (rejecting that is the
    /// balance validator's job, and it has to let the value through to report
    /// it). An unclamped result would drive the slider outside its own
    /// `0...100` range.
    static func percentage(ofAmount amount: Decimal, available: Decimal) -> Double? {
        guard available > 0 else { return nil }
        let ratio = (amount / available) * 100
        let clamped = min(max(ratio, 0), 100)
        return (clamped as NSDecimalNumber).doubleValue
    }

    /// The amount that `percentage` of `available` comes to.
    static func amount(forPercentage percentage: Double, available: Decimal) -> Decimal {
        available * (Decimal(percentage) / 100)
    }
}
