//
//  SendCryptoViewModel.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import SwiftUI
import BigInt

@MainActor
class SendCryptoViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var currentIndex = 1
    @Published var currentTitle = "send"
    @Published var priceRate = 0.0
    @Published var coinBalance: String = "0"
    
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
    
    func convertUSDToCoin(newValue: String, tx: SendTransaction, eth: EthplorerAPIService) {
        if let newValueDouble = Double(newValue) {
            var newCoinAmount = ""
            
            if    tx.coin.chain.name.lowercased() == Chain.Bitcoin.name.lowercased() ||
                tx.coin.chain.name.lowercased() == Chain.Litecoin.name.lowercased()
            {
                let rate = priceRate
                if rate > 0 {
                    let newValueCoin = newValueDouble / rate
                    newCoinAmount = newValueCoin != 0 ? String(format: "%.8f", newValueCoin) : ""
                }
            } else if tx.coin.chain.name.lowercased() == Chain.Ethereum.name.lowercased() {
                if tx.coin.ticker.uppercased() == Chain.Ethereum.ticker.uppercased() {
                    newCoinAmount = eth.addressInfo?.ETH.getAmountInEth(newValueDouble) ?? ""
                } else if let tokenInfo = tx.token {
                    newCoinAmount = tokenInfo.getAmountInTokens(newValueDouble)
                }
            } else if tx.coin.chain.name.lowercased() == Chain.THORChain.name.lowercased() {
                if let rate = CryptoPriceService.shared.cryptoPrices?.prices[Chain.THORChain.name.lowercased()]?["usd"], rate > 0 {
                    let newValueCoin = newValueDouble / rate
                    newCoinAmount = newValueCoin != 0 ? String(format: "%.8f", newValueCoin) : ""
                }
            } else if tx.coin.chain.name.lowercased() == Chain.Solana.name.lowercased() {
                if let rate = CryptoPriceService.shared.cryptoPrices?.prices[Chain.Solana.name.lowercased()]?["usd"], rate > 0 {
                    let newValueCoin = newValueDouble / rate
                    newCoinAmount = newValueCoin != 0 ? String(format: "%.9f", newValueCoin) : ""
                }
            }
            
            tx.amount = newCoinAmount
        } else {
            tx.amount = ""
        }
    }
    
    func convertToUSD(newValue: String, tx: SendTransaction, eth: EthplorerAPIService) {
        if let newValueDouble = Double(newValue) {
            var newValueUSD = ""
            
            if tx.coin.chain.name.lowercased() == Chain.Bitcoin.name.lowercased() ||
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
    
    private func updateState(tx: SendTransaction, utxoBtc: BitcoinUnspentOutputsService, utxoLtc: LitecoinUnspentOutputsService, eth: EthplorerAPIService, thor: ThorchainService, sol: SolanaService, cryptoPrice: CryptoPriceService, web3Service: Web3Service) {
        isLoading = true
            // TODO: move this logic into an abstraction
        
        if let priceRateUsd = cryptoPrice.cryptoPrices?.prices[tx.coin.chain.name.lowercased()]?["usd"] {
            priceRate = priceRateUsd
        }
        
        if tx.coin.chain.name.lowercased() == Chain.Bitcoin.name.lowercased() {
            coinBalance = utxoBtc.walletData?.balanceInBTC ?? "0"
        } else if tx.coin.chain.name.lowercased() == Chain.Litecoin.name.lowercased() {
            coinBalance = utxoLtc.walletData?.balanceInLTC ?? "0"
        } else if tx.coin.chain.name.lowercased() == Chain.Ethereum.name.lowercased() {
                // We need to pass it to the next view
            tx.eth = eth.addressInfo
            
            let gasPriceInGwei = BigInt(web3Service.gasPrice ?? 0) / BigInt(10).power(9)
            
            tx.gas = String(gasPriceInGwei)
            tx.nonce = Int64(web3Service.nonce ?? 0)
            
            if tx.token != nil {
                coinBalance = tx.token?.balanceString ?? ""
            } else {
                coinBalance = eth.addressInfo?.ETH.balanceString ?? "0.0"
            }
        } else if tx.coin.chain.name.lowercased() == Chain.THORChain.name.lowercased() {
            coinBalance = thor.formattedRuneBalance ?? "0.0"
            tx.gas = String("0.02")
        } else if tx.coin.chain.name.lowercased() == Chain.Solana.name.lowercased() {
            coinBalance = sol.formattedSolBalance ?? "0.0"
            if let feeInLamports = Int(sol.feeInLamports ?? "0") {
                tx.gas = String(feeInLamports)
            } else {
                tx.gas = "0"
            }
        }
        
        isLoading = false
    }
    
    func reloadTransactions(tx: SendTransaction, utxoBtc: BitcoinUnspentOutputsService, utxoLtc: LitecoinUnspentOutputsService, eth: EthplorerAPIService, thor: ThorchainService, sol: SolanaService, cryptoPrice: CryptoPriceService, web3Service: Web3Service) {
            // TODO: move this logic into an abstraction
            // ETH gets the price from other sourcers.
        Task {
            isLoading = true
            
            await cryptoPrice.fetchCryptoPrices(for: "bitcoin,litecoin,thorchain,solana", for: "usd")
            
            if tx.coin.chain.name.lowercased() == Chain.Bitcoin.name.lowercased() {
                await utxoBtc.fetchUnspentOutputs(for: tx.fromAddress)
            } else if tx.coin.chain.name.lowercased() == Chain.Litecoin.name.lowercased() {
                await utxoLtc.fetchLitecoinUnspentOutputs(for: tx.fromAddress)
            } else if tx.coin.chain.name.lowercased() == Chain.Ethereum.name.lowercased() {
                await eth.getEthInfo(for: tx.fromAddress)
                do {
                    try await web3Service.updateNonceAndGasPrice(forAddress: tx.fromAddress)
                } catch {
                    print(error)
                }
            } else if tx.coin.chain.name.lowercased() == Chain.Solana.name.lowercased() {
                await sol.getSolanaBalance(account: tx.fromAddress)
                await sol.fetchRecentBlockhash()
            }
            
            DispatchQueue.main.async {
                self.updateState(
                    tx: tx,
                    utxoBtc: utxoBtc,
                    utxoLtc: utxoLtc,
                    eth: eth,
                    thor: thor,
                    sol: sol,
                    cryptoPrice: cryptoPrice,
                    web3Service: web3Service
                )
                self.isLoading = false
            }
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
