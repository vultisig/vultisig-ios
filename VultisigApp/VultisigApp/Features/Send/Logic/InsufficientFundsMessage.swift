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

    // Exact digits, never rounded: a shortfall rounded up reads as the balance it is short of.
    private static func format(_ raw: BigInt, of coin: Coin) -> String {
        let amount = SendCryptoLogic.amountString(coin: coin, raw: raw)
            .replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? ".")
        return "\(amount) \(coin.ticker)"
    }
}
