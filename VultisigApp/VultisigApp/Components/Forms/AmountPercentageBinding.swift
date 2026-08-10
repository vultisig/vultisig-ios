//
//  AmountPercentageBinding.swift
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
///
/// ⚠️ **Not `PercentageAmountLogic`**, despite the similar name. That one serves
/// the Send / Swap / Limit Swap "25 / 50 / 75 / 100%" presets: it works from
/// `BigInt` base units, truncates to the asset's own precision, and only goes
/// percentage → amount. This one serves the function-transaction amount field,
/// works in `Decimal` against a human-readable balance, and is needed in both
/// directions because the field has to answer "what percentage is this?" for a
/// figure the user typed.
enum AmountPercentageBinding {

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

/// What the amount field should do in response to a change.
enum AmountPercentageSyncAction: Equatable {
    /// Recompute the amount from the percentage — the percentage is in charge.
    case setAmountFromPercentage
    /// Re-derive the percentage from the amount, leaving the amount untouched —
    /// the typed amount is in charge.
    case derivePercentageFromAmount
    /// The change was this field's own echo. Do nothing.
    case ignore
}

/// Which of the amount and the percentage is currently the source of truth in an
/// amount field, and therefore which one a change is allowed to overwrite.
///
/// This exists as a separate value type so it can be tested. It is the part of
/// `AmountTextField` most able to move money incorrectly — it decides whether a
/// slider may overwrite a figure the user typed — and SwiftUI `@State` and
/// `onChange` are not reachable from a unit test in this repo.
///
/// The field writes the percentage itself whenever the user types, which means it
/// then sees its own write come back through the same `onChange` that a real
/// slider interaction arrives on. Telling the two apart is the whole job:
///
/// - remembering only the derived VALUE is not enough. Once a real interaction
///   has moved away from it, a later move *back* to that same value would be
///   mistaken for the original echo — type the full balance, drag to 99%, drag
///   back to 100%, and the amount would be left at 99% while the screen reported
///   a MAX withdrawal. So a real interaction *spends* the remembered value.
/// - remembering only "was it typed" is not enough either, because a derived
///   percentage is `nil` when the balance has not loaded yet. Both facts are
///   tracked, so an amount typed against an empty balance is still recognised as
///   the user's when the balance arrives.
struct AmountPercentageSync {
    /// The percentage this field last derived from a typed amount. `nil` when
    /// nothing has been derived, or when the balance was unavailable at the time.
    private(set) var lastDerivedPercentage: Double?
    /// Whether the amount currently in the field was typed rather than produced
    /// by the percentage control.
    private(set) var amountIsUserTyped = false

    /// The user typed, and `percentage` is what that amount works out to.
    mutating func amountWasTyped(derivingPercentage percentage: Double?) {
        amountIsUserTyped = true
        lastDerivedPercentage = percentage
    }

    /// The bound percentage changed. Returns whether that was a real interaction
    /// with the slider or the buttons — and therefore whether it may rewrite the
    /// amount — or this field's own derived write echoing back.
    mutating func percentageChanged(to newValue: Double?) -> AmountPercentageSyncAction {
        if amountIsUserTyped, newValue == lastDerivedPercentage {
            return .ignore
        }
        amountIsUserTyped = false
        lastDerivedPercentage = nil
        return .setAmountFromPercentage
    }

    /// The available balance changed — typically an async read landing after the
    /// screen opened. Whichever side the user owns is the side that survives.
    func balanceChanged() -> AmountPercentageSyncAction {
        amountIsUserTyped ? .derivePercentageFromAmount : .setAmountFromPercentage
    }
}
