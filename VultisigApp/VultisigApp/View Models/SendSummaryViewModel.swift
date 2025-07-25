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
    
    func swapFeeString(_ tx: SwapTransaction) -> String {
        guard let inboundFeeDecimal = tx.inboundFeeDecimal else { return .empty }
        
        let fromCoin = feeCoin(tx: tx)
        let inboundFee = tx.toCoin.raw(for: inboundFeeDecimal)
        let fee = tx.toCoin.fiat(value: inboundFee) + fromCoin.fiat(value: tx.fee)
        return fee.formatToFiat(includeCurrencySymbol: true)
    }
    
    private func feeCoin(tx: SwapTransaction) -> Coin {
        switch tx.fromCoin.chainType {
        case .UTXO, .Solana, .THORChain, .Cosmos, .Polkadot, .Sui, .Ton, .Cardano, .Ripple, .Tron:
            return tx.fromCoin
        case .EVM:
            guard !tx.fromCoin.isNativeToken else { return tx.fromCoin }
            return tx.fromCoins.first(where: { $0.chain == tx.fromCoin.chain && $0.isNativeToken }) ?? tx.fromCoin
        }
    }
    
    func feesInReadable(tx: SendTransaction, vault: Vault) -> String {
        guard let nativeCoin = vault.nativeCoin(for: tx.coin) else { return .empty }
        let fee = nativeCoin.decimal(for: tx.gas)
        return RateProvider.shared.fiatBalanceString(value: fee, coin: nativeCoin)
    }
}
