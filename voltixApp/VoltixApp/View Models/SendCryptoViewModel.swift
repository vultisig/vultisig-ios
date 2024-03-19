//
//  SendCryptoViewModel.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import SwiftUI

@MainActor
class SendCryptoViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var currentIndex = 1
    @Published var currentTitle = "send"
    @Published var priceRate = 0.0
    
    let totalViews = 7
    let titles = ["send", "scan", "send", "pair", "verify", "keysign", "done"]
    
    func setMaxValues(tx: SendTransaction, utxoBtc: BitcoinUnspentOutputsService, utxoLtc: LitecoinUnspentOutputsService, eth: EthplorerAPIService, thor: ThorchainService, sol: SolanaService) {
        if tx.coin.chain.name.lowercased() == Chain.Bitcoin.name.lowercased() {
            let rate = priceRate
            if let walletData = utxoBtc.walletData {
                tx.amount = walletData.balanceInBTC
                tx.amountInUSD = String(format: "%.2f", walletData.balanceDecimal * rate)
            }
        } else if tx.coin.chain.name.lowercased() == Chain.Litecoin.name.lowercased() {
            let rate = priceRate
            if let walletData = utxoLtc.walletData {
                tx.amount = walletData.balanceInLTC
                tx.amountInUSD = String(format: "%.2f", walletData.balanceDecimal * rate)
            }
        } else if tx.coin.chain.name.lowercased() == Chain.Ethereum.name.lowercased() {
            if tx.coin.ticker.uppercased() == "ETH" {
                tx.amount = eth.addressInfo?.ETH.balanceString ?? "0.0"
                tx.amountInUSD = eth.addressInfo?.ETH.balanceInUsd.replacingOccurrences(of: "US$ ", with: "") ?? ""
            } else if let tokenInfo = tx.token {
                tx.amount = tokenInfo.balanceString
                tx.amountInUSD = tokenInfo.balanceInUsd.replacingOccurrences(of: "US$ ", with: "")
            }
        } else if tx.coin.chain.name.lowercased() == Chain.THORChain.name.lowercased() {
            if let priceRateUsd = CryptoPriceService.shared.cryptoPrices?.prices[Chain.THORChain.name.lowercased()]?["usd"] {
                tx.amountInUSD = thor.runeBalanceInUSD(usdPrice: priceRateUsd, includeCurrencySymbol: false) ?? "US$ 0,00"
            }
            tx.amount = thor.formattedRuneBalance ?? "0.00"
        } else if tx.coin.chain.name.lowercased() == Chain.Solana.name.lowercased() {
            if let priceRateUsd = CryptoPriceService.shared.cryptoPrices?.prices[Chain.Solana.name.lowercased()]?["usd"] {
                tx.amountInUSD = sol.solBalanceInUSD(usdPrice: priceRateUsd, includeCurrencySymbol: false) ?? "US$ 0,00"
            }
            tx.amount = sol.formattedSolBalance ?? "0.00"
        }
    }
    
    func convertToUSD(newValue: String, tx: SendTransaction, eth: EthplorerAPIService) {
        if let newValueDouble = Double(newValue) {
            var newValueUSD = ""
            
            if     tx.coin.chain.name.lowercased() == Chain.Bitcoin.name.lowercased() ||
                tx.coin.chain.name.lowercased() == Chain.Litecoin.name.lowercased()
            {
                let rate = priceRate
                newValueUSD = String(format: "%.2f", newValueDouble * rate)
            } else if tx.coin.chain.name.lowercased() == "ethereum" {
                if tx.coin.ticker.uppercased() == "ETH" {
                    newValueUSD = eth.addressInfo?.ETH.getAmountInUsd(newValueDouble) ?? ""
                } else if let tokenInfo = tx.token {
                    newValueUSD = tokenInfo.getAmountInUsd(newValueDouble)
                }
            } else if tx.coin.chain.name.lowercased() == Chain.THORChain.name.lowercased() {
                if let priceRateUsd = CryptoPriceService.shared.cryptoPrices?.prices[Chain.THORChain.name.lowercased()]?["usd"] {
                    newValueUSD = String(format: "%.2f", newValueDouble * priceRateUsd)
                }
            } else if tx.coin.chain.name.lowercased() == Chain.Solana.name.lowercased() {
                if let priceRateUsd = CryptoPriceService.shared.cryptoPrices?.prices[Chain.Solana.name.lowercased()]?["usd"] {
                    newValueUSD = String(format: "%.2f", newValueDouble * priceRateUsd)
                }
            }
            
            tx.amountInUSD = newValueUSD.isEmpty ? "" : newValueUSD
        } else {
            tx.amountInUSD = ""
        }
    }
    
    func moveToNextView() {
        currentIndex += 1
        currentTitle = titles[currentIndex-1]
    }
    
    func getProgress() -> Double {
        Double(currentIndex)/Double(totalViews)
    }
}
