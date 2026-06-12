//
//  CosmosStakingAmountFormatter.swift
//  VultisigApp
//
//  Shared base-unit conversion for Cosmos-SDK staking flows. The Cosmos
//  proto encoders take amounts as decimal strings in base units (e.g.
//  `"1500000"` for 1.5 LUNA at 6-decimals), so every per-flow builder needs
//  the same human-decimal → base-unit conversion. Factored out so all four
//  flows (delegate, undelegate, redelegate, withdrawRewards) cannot diverge
//  on rounding mode or comma-handling.
//
//  `Decimal`-based to avoid floating-point drift; `.down` rounding mirrors
//  the SDK encoder so we never silently over-stake when the user types a
//  value with more decimals than the chain accepts.
//

import Foundation

enum CosmosStakingAmountFormatter {
    /// Converts a human-decimal amount string (e.g. `"1.5"` or `"1,5"`) to
    /// the chain's base-unit string (e.g. `"1500000"` for 6-decimal LUNA).
    /// Returns `"0"` on any parse failure rather than throwing, so the
    /// downstream form validator surfaces "amount required" rather than a
    /// hard error from the builder.
    static func baseUnitsString(amount: String, decimals: Int) -> String {
        let normalized = amount.replacingOccurrences(of: ",", with: ".")
        guard let parsed = Decimal(string: normalized) else { return "0" }
        let multiplier = pow(Decimal(10), decimals)
        let raw = parsed * multiplier
        let handler = NSDecimalNumberHandler(
            roundingMode: .down,
            scale: 0,
            raiseOnExactness: false,
            raiseOnOverflow: false,
            raiseOnUnderflow: false,
            raiseOnDivideByZero: false
        )
        return NSDecimalNumber(decimal: raw).rounding(accordingToBehavior: handler).stringValue
    }
}
