//
//  SendCryptoDetailsViewModel.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import SwiftUI
import BigInt
import OSLog
import WalletCore
import Mediator

@MainActor
class SendCryptoViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var isValidAddress = false
    @Published var isValidForm = true
    @Published var showAlert = false
    @Published var currentIndex = 1
    @Published var currentTitle = "send"
    @Published var priceRate = 0.0
    @Published var coinBalance: String = "0"
    @Published var errorMessage = ""
    @Published var hash: String? = nil
    
    @EnvironmentObject var appState: ApplicationState
    @Published var thor = ThorchainService.shared
    @Published var sol: SolanaService = SolanaService.shared
    @Published var cryptoPrice = CryptoPriceService.shared
    @Published var utxo = BlockchairService.shared
    private let mediator = Mediator.shared
    
    let totalViews = 5
    let titles = ["send", "verify", "pair", "keysign", "done"]
    
    let logger = Logger(subsystem: "send-input-details", category: "transaction")
    
    func setMaxValues(tx: SendTransaction) {
        let coinName = tx.coin.chain.name.lowercased()
        let key: String = "\(tx.fromAddress)-\(coinName)"
        
        if  tx.coin.chain.chainType == ChainType.UTXO {
            tx.amount = utxo.blockchairData[key]?.address?.balanceInBTC ?? "0.0"
            tx.amountInUSD = utxo.blockchairData[key]?.address?.balanceInDecimalUSD ?? "0.0"
        } else if tx.coin.chain.name.lowercased() == Chain.Ethereum.name.lowercased() {
			tx.amount = tx.coin.balanceString
			tx.amountInUSD = tx.coin.balanceInUsd.replacingOccurrences(of: "US$ ", with: "")
        } else if tx.coin.chain.name.lowercased() == Chain.THORChain.name.lowercased() {
            Task{
                do{
                    let thorBalances = try await thor.fetchBalances(tx.fromAddress)
                    if let priceRateUsd = CryptoPriceService.shared.cryptoPrices?.prices[Chain.THORChain.name.lowercased()]?["usd"] {
                        tx.amountInUSD = thorBalances.runeBalanceInUSD(usdPrice: priceRateUsd, includeCurrencySymbol: false) ?? "US$ 0,00"
                    }
                    tx.amount = thorBalances.formattedRuneBalance() ?? "0.00"
                }catch{
                    print("fail to get THORChain balance,error:\(error.localizedDescription)")
                }
            }
        } else if tx.coin.chain.name.lowercased() == Chain.Solana.name.lowercased() {
            if let priceRateUsd = CryptoPriceService.shared.cryptoPrices?.prices[Chain.Solana.name.lowercased()]?["usd"] {
                tx.amountInUSD = sol.solBalanceInUSD(usdPrice: priceRateUsd, includeCurrencySymbol: false) ?? "US$ 0,00"
            }
            tx.amount = sol.formattedSolBalance ?? "0.00"
        }
    }
    
    func convertUSDToCoin(newValue: String, tx: SendTransaction) async {
        
        await cryptoPrice.fetchCryptoPrices()
        
        if let priceRateUsd = cryptoPrice.cryptoPrices?.prices[tx.coin.chain.name.lowercased()]?["usd"] {
            priceRate = priceRateUsd
        }
        
        if let newValueDouble = Double(newValue) {
            var newCoinAmount = ""
            
            if  tx.coin.chain.chainType == ChainType.UTXO {
                let rate = priceRate
                if rate > 0 {
                    let newValueCoin = newValueDouble / rate
                    newCoinAmount = newValueCoin != 0 ? String(format: "%.8f", newValueCoin) : ""
                }
            } else if tx.coin.chain.name.lowercased() == Chain.Ethereum.name.lowercased() {
				newCoinAmount = tx.coin.getAmountInTokens(newValueDouble)
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
    
    func convertToUSD(newValue: String, tx: SendTransaction) async {
        
        await cryptoPrice.fetchCryptoPrices()
        
        if let priceRateUsd = cryptoPrice.cryptoPrices?.prices[tx.coin.chain.name.lowercased()]?["usd"] {
            priceRate = priceRateUsd
        }
        
        if let newValueDouble = Double(newValue) {
            var newValueUSD = ""
            
            if  tx.coin.chain.chainType == ChainType.UTXO {
                let rate = priceRate
                newValueUSD = String(format: "%.2f", newValueDouble * rate)
            } else if tx.coin.chain.name.lowercased() == "ethereum" {
				newValueUSD = tx.coin.getAmountInUsd(newValueDouble)
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
    
    func validateAddress(tx: SendTransaction, address: String) {
        let chainName = tx.coin.chain.name.lowercased().replacingOccurrences(of: "-", with: "")
        
        guard let coinType = CoinType.from(string: chainName) else {
            print("Coin type not found on Wallet Core")
            return
        }
        
        isValidAddress = coinType.validate(address: address)
    }
    
    func validateForm(tx: SendTransaction) -> Bool {
        // Reset validation state at the beginning
        errorMessage = ""
        isValidForm = true
        
        // Validate the "To" address
        if !isValidAddress {
            errorMessage = "validAddressError"
            showAlert = true
            logger.log("Invalid address.")
            isValidForm = false
        }
        
        let amount = tx.amountDecimal
        let gasFee = tx.gasDecimal
        
        if amount <= 0 {
            errorMessage = "positiveAmountError"
            showAlert = true
            logger.log("Invalid or non-positive amount.")
            isValidForm = false
            return isValidForm
        }
        
        if gasFee <= 0 {
            errorMessage = "nonNegativeFeeError"
            showAlert = true
            logger.log("Invalid or negative fee.")
            isValidForm = false
            return isValidForm
        }
        
        let coinName = tx.coin.chain.name.lowercased()
        let key: String = "\(tx.fromAddress)-\(coinName)"
        
        if  tx.coin.chain.chainType == ChainType.UTXO {
            let walletBalanceInSats = utxo.blockchairData[key]?.address?.balance ?? 0
            let totalTransactionCostInSats = tx.amountInSats + tx.feeInSats
            print("Total transaction cost: \(totalTransactionCostInSats)")
            
            if totalTransactionCostInSats > walletBalanceInSats {
                errorMessage = "walletBalanceExceededError"
                showAlert = true
                logger.log("Total transaction cost exceeds wallet balance.")
                isValidForm = false
            }
            
        } else if tx.coin.chain.name.lowercased() == Chain.Ethereum.name.lowercased() {
//            let ethBalanceInWei = Int(eth.rawBalance) ?? 0// it is in WEI
//            
//            if tx.coin.ticker.uppercased() == "ETH" {
//                if tx.totalEthTransactionCostWei > ethBalanceInWei {
//                    errorMessage = "walletBalanceExceededError"
//                    showAlert = true
//                    logger.log("Total transaction cost exceeds wallet balance.")
//                    isValidForm = false
//                }
//                
//            } else {
//                if let tokenInfo = eth.tokens?.first(where: { $0.symbol == tx.coin.ticker.uppercased() }) {
//                    print("tx.feeInWei \(tx.feeInWei)")
//                    print("ethBalanceInWei \(ethBalanceInWei)")
//                    
//                    print("has eth to pay the fee?  \(tx.feeInWei > ethBalanceInWei)")
//                    
//                    if tx.feeInWei > ethBalanceInWei {
//                        errorMessage = "mustHaveETHError"
//                        showAlert = true
//                        logger.log("You must have ETH in to send any TOKEN, so you can pay the fees. \n")
//                        isValidForm = false
//                    }
//                    
//					let tokenBalance = Int(tx.coin.rawBalance) ?? 0
//                    
//                    if tx.amountInTokenWei > tokenBalance {
//                        errorMessage = "walletBalanceExceededError"
//                        showAlert = true
//                        logger.log("Total transaction cost exceeds wallet balance.")
//                        isValidForm = false
//                    }
//                }
//            }
        } else if tx.coin.chain.name.lowercased() == Chain.THORChain.name.lowercased() {
            
        } else if tx.coin.chain.name.lowercased() == Chain.Solana.name.lowercased() {
            
            guard let walletBalanceInLamports = sol.balance else {
                errorMessage = "unavailableBalanceError"
                showAlert = true
                logger.log("Wallet balance is not available for Solana.")
                isValidForm = false
                return isValidForm
            }
            
            let optionalGas: String? = tx.gas
            guard let feeStr = optionalGas, let feeInLamports = Decimal(string: feeStr) else {
                errorMessage = "invalidGasFeeError"
                showAlert = true
                logger.log("Invalid gas fee for Solana.")
                isValidForm = false
                return isValidForm
            }
            
            guard let amountInSOL = Decimal(string: tx.amount) else {
                errorMessage = "invalidTransactionAmountError"
                showAlert = true
                logger.log("Invalid transaction amount for Solana.")
                isValidForm = false
                return isValidForm
            }
            
            let amountInLamports = amountInSOL * Decimal(1_000_000_000)
            
            let totalCostInLamports = amountInLamports + feeInLamports
            if totalCostInLamports > Decimal(walletBalanceInLamports) {
                errorMessage = "walletBalanceExceededSolanaError"
                showAlert = true
                logger.log("Total transaction cost exceeds wallet balance for Solana.")
                isValidForm = false
            }
        }
        
        return isValidForm
    }
    
    func moveToNextView() {
        currentIndex += 1
        currentTitle = titles[currentIndex-1]
    }
    
    func getProgress() -> Double {
        Double(currentIndex)/Double(totalViews)
    }
    
    func stopMediator() {
        self.mediator.stop()
        logger.info("mediator server stopped.")
    }
}
