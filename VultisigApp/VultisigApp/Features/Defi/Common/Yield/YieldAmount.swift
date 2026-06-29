//
//  YieldAmount.swift
//  VultisigApp
//

import Foundation
import BigInt

/// Decimal ⇄ base-unit conversion shared by the yield forms. Goes through the
/// string form (matching the Circle withdraw path) so floating `Decimal` scaling
/// never produces a fractional remainder.
enum YieldAmount {
    /// Converts a human-readable amount into integer base units. Returns `nil`
    /// (rather than coercing to `0`) when the scaled value doesn't parse, so a
    /// bad conversion can't silently become a zero-amount transaction — callers
    /// must block request construction on `nil`.
    static func baseUnits(_ amount: Decimal, decimals: Int) -> BigInt? {
        let scaled = amount * pow(Decimal(10), decimals)
        var scaledCopy = scaled
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaledCopy, 0, .plain)
        // Reject sub-unit precision instead of truncating it — a value that
        // doesn't land on a whole base unit must fail, not silently shrink.
        guard rounded == scaled else { return nil }
        return BigInt(NSDecimalNumber(decimal: rounded).stringValue)
    }

    static func humanAmount(_ value: BigInt, decimals: Int) -> Decimal {
        guard let decimal = Decimal(string: value.description) else { return .zero }
        return decimal / pow(Decimal(10), decimals)
    }
}

/// Projected yield on a deposit, in the deposit asset's units. Pure so the
/// percent→fraction conversion (the load-bearing bit) is unit-testable.
struct YieldEstimate: Equatable {
    /// Yield accrued over one month: `yearly / 12`.
    let monthly: Decimal
    /// Yield accrued over one year: `amount × apy`, with `apy = apyPercent / 100`.
    let yearly: Decimal

    /// Builds an estimate from the entered amount and an APY expressed as a
    /// PERCENT (e.g. `12.5` ⇒ 12.5%). Returns `nil` when either input is missing
    /// or non-positive, so callers can hide the preview instead of showing `0`.
    static func make(amount: Decimal?, apyPercent: Decimal?) -> YieldEstimate? {
        guard let amount, amount > 0, let apyPercent, apyPercent > 0 else {
            return nil
        }
        let yearly = amount * apyPercent / 100
        return YieldEstimate(monthly: yearly / 12, yearly: yearly)
    }
}
