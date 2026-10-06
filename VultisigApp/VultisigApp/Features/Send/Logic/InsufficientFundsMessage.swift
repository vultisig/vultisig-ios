//
//  InsufficientFundsMessage.swift
//  VultisigApp
//

import BigInt
import Foundation

/// The insufficient-funds message that names the exact asset a send is short of,
/// how much the send needs and how much the vault holds.
enum InsufficientFundsMessage {
    static func text(coin: Coin, required: BigInt, available: BigInt, includesNetworkCosts: Bool) -> String {
        let key = includesNetworkCosts ? "insufficientFundsIncludingNetworkCosts" : "insufficientFundsAsset"
        return String(format: key.localized, coin.ticker, format(required, of: coin), format(available, of: coin))
    }

    // Exact digits from integer division: Double and Decimal both drop digits on
    // wide values, and a shortfall rounded up reads as the balance it is short of.
    private static func format(_ raw: BigInt, of coin: Coin) -> String {
        guard coin.decimals > 0 else { return "\(raw) \(coin.ticker)" }
        let (whole, fraction) = raw.quotientAndRemainder(dividingBy: BigInt(10).power(coin.decimals))
        let padded = String(repeating: "0", count: coin.decimals - fraction.description.count) + fraction.description
        let trimmed = padded.replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
        let amount = trimmed.isEmpty ? "\(whole)" : "\(whole)\(Locale.current.decimalSeparator ?? ".")\(trimmed)"
        return "\(amount) \(coin.ticker)"
    }
}
