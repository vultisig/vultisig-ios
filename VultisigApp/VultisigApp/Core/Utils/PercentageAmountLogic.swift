//
//  PercentageAmountLogic.swift
//  VultisigApp
//
//  Shared math behind the "25 / 50 / 75 / 100%" amount presets. Send, Swap and
//  Limit Swap all funnel through here so the three flows cannot drift apart on
//  how much precision a preset amount is allowed to carry.
//

import BigInt
import Foundation

enum PercentageAmountLogic {

    /// Decimal places a fractional preset amount may carry.
    ///
    /// Capped at 8 — the widest precision the amount inputs render — and never
    /// above what the asset itself can represent, so a preset never fills the
    /// field with digits the chain would have to drop.
    static func decimalPlaces(coinDecimals: Int) -> Int {
        min(8, max(0, coinDecimals))
    }

    /// Amount string for `percentage`% of `rawBalance` (base units).
    ///
    /// 100% converts the raw balance at the asset's own precision, so the
    /// preset strands nothing; the fractional presets truncate to
    /// `decimalPlaces(coinDecimals:)`. Truncating rather than rounding keeps
    /// every result at or below the balance.
    ///
    /// Callers that must reserve a network fee (a native 100% / Max) subtract
    /// it from `rawBalance` before calling — this function only divides.
    static func amountText(percentage: Int, rawBalance: BigInt, coinDecimals: Int) -> String {
        let percentage = min(max(percentage, 0), 100)
        let decimals = max(0, coinDecimals)
        guard rawBalance > 0 else { return "0" }

        guard percentage < 100 else {
            return exactAmountText(rawBalance: rawBalance, decimals: decimals)
        }

        let balance = (Decimal(string: rawBalance.description) ?? .zero) / pow(10, decimals)
        let digits = decimalPlaces(coinDecimals: decimals)
        let amount = (balance * Decimal(percentage) / 100).truncated(toPlaces: digits)
        return amount.formatToDecimal(digits: digits)
    }

    /// Exact base-units → decimal-string conversion, by string surgery.
    ///
    /// `Decimal.formatToDecimal` renders through `NumberFormatter`, which is
    /// Double-backed and silently rounds past ~16 significant digits — enough
    /// to round an 18-decimal balance *up*, above what the wallet actually
    /// holds. The 100% preset has to show the balance itself, so it is built
    /// from the digits directly. `rawBalance` is > 0 by the caller's guard.
    private static func exactAmountText(rawBalance: BigInt, decimals: Int) -> String {
        let digits = String(rawBalance)
        guard decimals > 0 else { return digits }

        // Left-pad so there is at least one whole digit before the point.
        let padded = digits.count > decimals
            ? digits
            : String(repeating: "0", count: decimals - digits.count + 1) + digits

        let split = padded.index(padded.endIndex, offsetBy: -decimals)
        let whole = String(padded[..<split])
        var fraction = String(padded[split...])
        while fraction.last == "0" { fraction.removeLast() }

        guard !fraction.isEmpty else { return whole }
        return whole + (Locale.current.decimalSeparator ?? ".") + fraction
    }
}
