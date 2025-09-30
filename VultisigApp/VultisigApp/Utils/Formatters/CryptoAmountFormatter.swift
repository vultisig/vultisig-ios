//
//  CryptoAmountFormatter.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/08/2025.
//

enum CryptoAmountFormatter {
    static func feesInReadable(tx: SendTransaction, vault: Vault) -> String {
        guard let nativeCoin = vault.nativeCoin(for: tx.coin) else { return .empty }
        let fee = nativeCoin.decimal(for: tx.fee)
        return RateProvider.shared.fiatBalanceString(value: fee, cryptoId: nativeCoin.cryptoId())
    }
}
