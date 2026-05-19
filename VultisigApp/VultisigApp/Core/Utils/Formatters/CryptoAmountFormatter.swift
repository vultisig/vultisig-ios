//
//  CryptoAmountFormatter.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/08/2025.
//

enum CryptoAmountFormatter {
    /// Decision 2 win: vault is non-optional on SendTransaction, so the
    /// `vault:` parameter goes away — read it off `tx.vault` directly.
    static func feesInReadable(tx: SendTransaction) -> String {
        guard let nativeCoin = tx.vault.nativeCoin(for: tx.coin) else { return .empty }
        let fee = nativeCoin.decimal(for: tx.fee)
        // Use fee-specific formatting with more decimal places (5 instead of 2)
        return RateProvider.shared.fiatFeeString(value: fee, coin: nativeCoin)
    }
}
