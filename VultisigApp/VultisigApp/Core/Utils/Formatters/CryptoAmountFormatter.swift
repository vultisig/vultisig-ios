//
//  CryptoAmountFormatter.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/08/2025.
//

import Foundation

enum CryptoAmountFormatter {
    /// Decision 2 win: vault is non-optional on SendTransaction, so the
    /// `vault:` parameter goes away — read it off `tx.vault` directly.
    static func feesInReadable(tx: SendTransaction) -> String {
        guard let nativeCoin = tx.vault.nativeCoin(for: tx.coin) else { return .empty }
        let fee = nativeCoin.decimal(for: tx.fee)
        // Use fee-specific formatting with more decimal places (5 instead of 2)
        return RateProvider.shared.fiatFeeString(value: fee, coin: nativeCoin)
    }

    /// Formatted fiat value of a coin amount for the verify/summary surfaces
    /// (e.g. "$12.34"), sharing the fee's `RateProvider` price source
    /// (`Coin.fiat(decimal:)`). Returns empty for a non-positive amount,
    /// when no rate is available, or when the fiat value is below one cent —
    /// the standard 2-decimal fiat formatter rounds down, so a priced dust
    /// amount would otherwise still render as a misleading "$0.00". Single
    /// source for the amount-fiat semantics on the initiator send verify
    /// header, the co-sign summary, and the keysign hero rows.
    static func amountInFiat(coin: Coin, amount: Decimal) -> String {
        guard amount > 0, RateProvider.shared.hasRate(for: coin) else { return .empty }
        let fiat = coin.fiat(decimal: amount)
        let oneCent = Decimal(sign: .plus, exponent: -2, significand: 1)
        guard fiat >= oneCent else { return .empty }
        return fiat.formatToFiat(includeCurrencySymbol: true)
    }
}
