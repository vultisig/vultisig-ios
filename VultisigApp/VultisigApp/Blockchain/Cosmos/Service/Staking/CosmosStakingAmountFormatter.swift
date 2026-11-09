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
    /// Converts an amount to the chain's base-unit string (e.g. `"1500000"` for
    /// 1.5 LUNA at 6 decimals). Takes the `Decimal` the form parsed: re-parsing
    /// display text breaks on grouping ("1,234.5" read as 1.234).
    static func baseUnitsString(amount: Decimal, decimals: Int) -> String {
        let raw = amount * pow(Decimal(10), decimals)
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
