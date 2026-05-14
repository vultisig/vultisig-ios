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

        if tx.fromCoin.chain == tx.toCoin.chain {
            return "\(formattedAmount) \(tx.fromCoin.ticker)"
        } else {
            return "\(formattedAmount) \(tx.fromCoin.ticker) (\(tx.fromCoin.chain.name))"
        }
    }

    func getToAmount(_ tx: SwapTransaction) -> String {
        let formattedAmount = tx.toAmountDecimal.formatForDisplay()

        if tx.fromCoin.chain == tx.toCoin.chain {
            return "\(formattedAmount) \(tx.toCoin.ticker)"
        } else {
            return "\(formattedAmount) \(tx.toCoin.ticker) (\(tx.toCoin.chain.name))"
        }
    }

    func swapFeeString(_ tx: SwapTransaction) -> String {
        // `tx.gas` is gas price (wei/gas for EVM) — converting it directly to
        // fiat understates the network fee by ~6 orders of magnitude. `tx.fee`
        // is the precomputed total payable network fee in the chain's smallest
        // unit, which is what we actually owe.
        let networkFee = tx.feeCoin.fiat(value: tx.fee)

        if let swapFeeBigInt = tx.quote.evmSwapFeeBigInt {
            let feeDecimal = tx.feeCoin.decimal(for: swapFeeBigInt)
            let swapFee = tx.feeCoin.fiat(decimal: feeDecimal)
            return (swapFee + networkFee).formatToFiat(includeCurrencySymbol: true)
        }

        guard let inboundFeeDecimal = tx.quote.inboundFeeDecimal(toCoin: tx.toCoin) else { return .empty }

        let inboundFee = tx.toCoin.raw(for: inboundFeeDecimal)
        let fee = tx.toCoin.fiat(value: inboundFee) + networkFee
        return fee.formatToFiat(includeCurrencySymbol: true)
    }

    func feesInReadable(tx: SendTransaction, vault: Vault) -> String {
        guard let nativeCoin = vault.nativeCoin(for: tx.coin) else {
            return .empty
        }

        // Use tx.fee (total fee amount) instead of tx.gas (sats/byte rate) like Android does
        let feeToUse = (tx.coin.chainType == .UTXO || tx.coin.chainType == .Cardano) ? tx.fee : tx.gas

        let fee = nativeCoin.decimal(for: feeToUse)
        // Use fee-specific formatting with more decimal places (5 instead of 2)
        return RateProvider.shared.fiatFeeString(value: fee, coin: nativeCoin)
    }
}
