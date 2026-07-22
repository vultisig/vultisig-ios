//
//  SendSummaryViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-11-19.
//

import BigInt
import Foundation

@MainActor
class SendSummaryViewModel: ObservableObject {
    func getFromAmount(_ tx: SwapTransaction) -> String {
        let formattedAmount = tx.fromAmount.formatForDisplay()
        return "\(formattedAmount) \(tx.fromCoin.ticker)"
    }

    func getToAmount(_ tx: SwapTransaction) -> String {
        let formattedAmount = tx.toAmountDecimal.formatForDisplay()
        return "\(formattedAmount) \(tx.toCoin.ticker)"
    }

    /// Decision 2 win: vault is non-optional on SendTransaction, so the vault
    /// parameter is no longer needed — read it off `tx.vault` directly.
    func feesInReadable(tx: SendTransaction) -> String {
        guard let nativeCoin = tx.vault.nativeCoin(for: tx.coin) else {
            return .empty
        }

        // Use tx.fee (total fee amount) instead of tx.gas (sats/byte rate) like Android does
        let feeToUse = (tx.coin.chainType == .UTXO || tx.coin.chainType == .Cardano) ? tx.fee : tx.gas

        let fee = nativeCoin.decimal(for: feeToUse)
        // Use fee-specific formatting with more decimal places (5 instead of 2)
        return RateProvider.shared.fiatFeeString(value: fee, coin: nativeCoin)
    }
}
