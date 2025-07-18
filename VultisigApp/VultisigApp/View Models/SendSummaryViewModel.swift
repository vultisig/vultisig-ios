//
//  SendSummaryViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-11-19.
//

import Foundation

@MainActor
class SendSummaryViewModel: ObservableObject {
    func getFromAmount(_ tx: SwapTransaction, selectedCurrency: SettingsCurrency) -> String {
        let formattedAmount = tx.fromAmountDecimal.formatForDisplay()
            
        if tx.fromCoin.chain == tx.toCoin.chain {
            return "\(formattedAmount) \(tx.fromCoin.ticker)"
        } else {
            return "\(formattedAmount) \(tx.fromCoin.ticker) (\(tx.fromCoin.chain.ticker))"
        }
    }

    func getToAmount(_ tx: SwapTransaction, selectedCurrency: SettingsCurrency) -> String {
        let formattedAmount = tx.toAmountDecimal.formatForDisplay()
            
        if tx.fromCoin.chain == tx.toCoin.chain {
            return "\(formattedAmount) \(tx.toCoin.ticker)"
        } else {
            return "\(formattedAmount) \(tx.toCoin.ticker) (\(tx.toCoin.chain.ticker))"
        }
    }
}
