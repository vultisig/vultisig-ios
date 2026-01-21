//
//  AmountFormatter.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 20/10/2025.
//

import Foundation

enum AmountFormatter {
    static func formatCryptoAmount(value: Decimal, coin: CoinMeta) -> String {
        formatCryptoAmount(value: value, ticker: coin.ticker)
    }

    static func formatCryptoAmount(value: Decimal, coin: Coin) -> String {
        formatCryptoAmount(value: value, ticker: coin.ticker)
    }

    static func formatCryptoAmount(value: Decimal, ticker: String) -> String {
        "\(value.formatForDisplay()) \(ticker)"
    }
}
