//
//  SendSummaryViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-11-19.
//

import Foundation

@MainActor
class SendSummaryViewModel {
    func getFromAmount(_ tx: SwapTransaction, selectedCurrency: SettingsCurrency) -> String {
        if tx.fromCoin.chain == tx.toCoin.chain {
            return "\(tx.fromAmount.formatCurrencyWithSeparators(selectedCurrency)) \(tx.fromCoin.ticker)"
        } else {
            return "\(tx.fromAmount.formatCurrencyWithSeparators(selectedCurrency)) \(tx.fromCoin.ticker) (\(tx.fromCoin.chain.ticker))"
        }
    }

    func getToAmount(_ tx: SwapTransaction, selectedCurrency: SettingsCurrency) -> String {
        if tx.fromCoin.chain == tx.toCoin.chain {
            return "\(tx.toAmountDecimal.description.formatCurrencyWithSeparators(selectedCurrency)) \(tx.toCoin.ticker)"
        } else {
            return "\(tx.toAmountDecimal.description.formatCurrencyWithSeparators(selectedCurrency)) \(tx.toCoin.ticker) (\(tx.toCoin.chain.ticker))"
        }
    }
    
    func swapFeeString(_ tx: SwapTransaction) -> String {
        guard let inboundFeeDecimal = tx.inboundFeeDecimal else { return .empty }
        
        let fromCoin = feeCoin(tx: tx)
        let inboundFee = tx.toCoin.raw(for: inboundFeeDecimal)
        let fee = tx.toCoin.fiat(value: inboundFee) + fromCoin.fiat(value: tx.fee)
        return fee.formatToFiat(includeCurrencySymbol: true)
    }
    
    private func feeCoin(tx: SwapTransaction) -> Coin {
        switch tx.fromCoin.chainType {
        case .UTXO, .Solana, .THORChain, .Cosmos, .Polkadot, .Sui, .Ton, .Cardano:
            return tx.fromCoin
        case .EVM:
            guard !tx.fromCoin.isNativeToken else { return tx.fromCoin }
            return tx.fromCoins.first(where: { $0.chain == tx.fromCoin.chain && $0.isNativeToken }) ?? tx.fromCoin
        }
    }
}
