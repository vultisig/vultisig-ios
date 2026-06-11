//
//  TerraClassicTax.swift
//  VultisigApp
//

import Foundation
import BigInt

/// Terra Classic (columbus-5) charges a proportional **burn tax** on every
/// `MsgSend`, paid in the send denom on top of the gas fee. The rate lives in
/// the chain's `x/tax` module (`burn_tax_rate`, currently 0.5%) and is fetched
/// live; this helper holds the conservative fallback and the pure tax math so
/// the signed fee, the validated fee, and the displayed fee stay consistent.
enum TerraClassicTax {

    /// Conservative fallback burn-tax rate used when the live `x/tax` params
    /// can't be fetched/decoded. Matches current governance (0.5%). Failing
    /// closed (taxing) rather than open (0%) avoids signing a tx the chain then
    /// rejects at broadcast.
    static let fallbackBurnTaxRate = Decimal(string: "0.005")! // swiftlint:disable:this force_unwrapping

    /// Burn tax on a send `amount` (in the denom's smallest unit) at `rate`,
    /// rounded **up** so the signed fee never undershoots the chain's check.
    static func burnTax(amount: BigInt, rate: Decimal) -> BigInt {
        guard amount > 0, rate > 0 else { return 0 }

        // amount * rate, rounded up. Work in Decimal then ceil to an integer.
        let amountDecimal = Decimal(string: amount.description) ?? 0
        var product = amountDecimal * rate
        var rounded = Decimal()
        NSDecimalRound(&rounded, &product, 0, .up)

        // `rounded` is a non-negative integer Decimal, so its stringValue is a
        // plain base-10 integer string the BigInt initializer accepts.
        return BigInt(NSDecimalNumber(decimal: rounded).stringValue) ?? 0
    }

    /// Parse a decimal-string `burn_tax_rate` from the LCD into a `Decimal`,
    /// falling back to the conservative default on any parse failure.
    static func parseRate(_ raw: String) -> Decimal {
        guard let value = Decimal(string: raw), value >= 0 else {
            return fallbackBurnTaxRate
        }
        return value
    }
}
