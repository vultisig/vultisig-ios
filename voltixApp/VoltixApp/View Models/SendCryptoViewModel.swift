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
    
	@EnvironmentObject var appState: ApplicationState
    @Published var thor = ThorchainService.shared
    @Published var sol: SolanaService = SolanaService.shared
    @Published var cryptoPrice = CryptoPriceService.shared
	@StateObject var utxo = BlockchairService.shared

	
    let totalViews = 3
    let titles = ["send", "scan", "send", "pair", "verify", "keysign", "done"]
    
    let logger = Logger(subsystem: "send-input-details", category: "transaction")
    
    func setMaxValues(tx: SendTransaction, eth: EthplorerAPIService) {
		let coinName = tx.coin.chain.name.lowercased()
		let key: String = "\(tx.fromAddress)-\(coinName)"
		
		if  tx.coin.chain.chainType == ChainType.UTXO {
			tx.amount = utxo.blockchairData[key]?.address?.balanceInBTC ?? "0.0"
			tx.amountInUSD = utxo.blockchairData[key]?.address?.balanceInDecimalUSD ?? "0.0"
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
    
	func convertUSDToCoin(newValue: String, tx: SendTransaction, eth: EthplorerAPIService) async {
		
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
    
    func convertToUSD(newValue: String, tx: SendTransaction, eth: EthplorerAPIService) async {
		
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
    
//    func updateState(tx: SendTransaction, eth: EthplorerAPIService, web3Service: Web3Service) {
//		isLoading = true
//		
//		if let priceRateUsd = cryptoPrice.cryptoPrices?.prices[tx.coin.chain.name.lowercased()]?["usd"] {
//			priceRate = priceRateUsd
//		}
//		
//		let coinName = tx.coin.chain.name.lowercased()
//		let key: String = "\(tx.fromAddress)-\(coinName)"
//		
//		if  tx.coin.chain.chainType == ChainType.UTXO {
//			coinBalance = utxo.blockchairData[key]?.address?.balanceInBTC ?? "0.0"
//		} else if tx.coin.chain.name.lowercased() == Chain.Ethereum.name.lowercased() {
//			// We need to pass it to the next view
//			tx.eth = eth.addressInfo
//			
//			let gasPriceInGwei = BigInt(web3Service.gasPrice ?? 0) / BigInt(10).power(9)
//			
//			tx.gas = String(gasPriceInGwei)
//			tx.nonce = Int64(web3Service.nonce ?? 0)
//			
//			if tx.token != nil {
//				coinBalance = tx.token?.balanceString ?? ""
//			} else {
//				coinBalance = eth.addressInfo?.ETH.balanceString ?? "0.0"
//			}
//		} else if tx.coin.chain.name.lowercased() == Chain.THORChain.name.lowercased() {
//			coinBalance = thor.formattedRuneBalance ?? "0.0"
//			tx.gas = String("0.02")
//		} else if tx.coin.chain.name.lowercased() == Chain.Solana.name.lowercased() {
//			coinBalance = sol.formattedSolBalance ?? "0.0"
//			if let feeInLamports = Int(sol.feeInLamports ?? "0") {
//				tx.gas = String(feeInLamports)
//			} else {
//				tx.gas = "0"
//			}
//		}
//		
//		isLoading = false
//    }
//    
//    func reloadTransactions(tx: SendTransaction, eth: EthplorerAPIService, web3Service: Web3Service) {
//		Task {
//			isLoading = true
//			
//			await cryptoPrice.fetchCryptoPrices()
//			
//			let coinName = tx.coin.chain.name.lowercased()
//			
//			if  tx.coin.chain.chainType == ChainType.UTXO {
//				await utxo.fetchBlockchairData(for: tx.fromAddress, coinName: coinName)
//			} else if tx.coin.chain.name.lowercased() == Chain.Ethereum.name.lowercased() {
//				await eth.getEthInfo(for: tx.fromAddress)
//				do {
//					try await web3Service.updateNonceAndGasPrice(forAddress: tx.fromAddress)
//				} catch {
//					print(error)
//				}
//			} else if tx.coin.chain.name.lowercased() == Chain.Solana.name.lowercased() {
//				await sol.getSolanaBalance(account: tx.fromAddress)
//				await sol.fetchRecentBlockhash()
//			}
//			
//			DispatchQueue.main.async {
//				self.updateState(tx: tx, eth: eth, web3Service: web3Service)
//				self.isLoading = false
//			}
//		}
//    }
    
    func validateAddress(tx: SendTransaction, address: String) {
		let chainName = tx.coin.chain.name.lowercased().replacingOccurrences(of: "-", with: "")
		
		guard let coinType = CoinType.from(string: chainName) else {
			print("Coin type not found on Wallet Core")
			return
		}
		
		isValidAddress = coinType.validate(address: address)
    }
    
    func validateForm(tx: SendTransaction, eth: EthplorerAPIService) -> Bool {
			// Reset validation state at the beginning
		errorMessage = ""
		isValidForm = true
		
			// Validate the "To" address
		if !isValidAddress {
			errorMessage += "Please enter a valid address. \n"
			logger.log("Invalid address.")
			isValidForm = false
		}
		
		let amount = tx.amountDecimal
		let gasFee = tx.gasDecimal
		
		if amount <= 0 {
			errorMessage += "Amount must be a positive number. Please correct your entry. \n"
			logger.log("Invalid or non-positive amount.")
			isValidForm = false
			return isValidForm
		}
		
		if gasFee <= 0 {
			errorMessage += "Fee must be a non-negative number. Please correct your entry. \n"
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
				errorMessage += "The combined amount and fee exceed your wallet's balance. Please adjust to proceed. \n"
				logger.log("Total transaction cost exceeds wallet balance.")
				isValidForm = false
			}
			
		} else if tx.coin.chain.name.lowercased() == Chain.Ethereum.name.lowercased() {
			let ethBalanceInWei = Int(eth.addressInfo?.ETH.rawBalance ?? "0") ?? 0 // it is in WEI
			
			if tx.coin.ticker.uppercased() == "ETH" {
				if tx.totalEthTransactionCostWei > ethBalanceInWei {
					errorMessage += "The combined amount and fee exceed your wallet's balance. Please adjust to proceed. \n"
					logger.log("Total transaction cost exceeds wallet balance.")
					isValidForm = false
				}
				
			} else {
				if let tokenInfo = eth.addressInfo?.tokens?.first(where: { $0.tokenInfo.symbol == tx.coin.ticker.uppercased() }) {
					print("tx.feeInWei \(tx.feeInWei)")
					print("ethBalanceInWei \(ethBalanceInWei)")
					
					print("has eth to pay the fee?  \(tx.feeInWei > ethBalanceInWei)")
					
					if tx.feeInWei > ethBalanceInWei {
						errorMessage += "You must have ETH in to send any TOKEN, so you can pay the fees. \n"
						logger.log("You must have ETH in to send any TOKEN, so you can pay the fees. \n")
						isValidForm = false
					}
					
					let tokenBalance = Int(tokenInfo.rawBalance) ?? 0
					
					if tx.amountInTokenWei > tokenBalance {
						errorMessage += "Total transaction cost exceeds wallet balance. \n"
						logger.log("Total transaction cost exceeds wallet balance.")
						isValidForm = false
					}
				}
			}
		} else if tx.coin.chain.name.lowercased() == Chain.THORChain.name.lowercased() {
			
		} else if tx.coin.chain.name.lowercased() == Chain.Solana.name.lowercased() {
			
			guard let walletBalanceInLamports = sol.balance else {
				errorMessage += "Wallet balance is not available. \n"
				logger.log("Wallet balance is not available for Solana.")
				isValidForm = false
				return isValidForm
			}
			
			let optionalGas: String? = tx.gas
			guard let feeStr = optionalGas, let feeInLamports = Decimal(string: feeStr) else {
				errorMessage += "Invalid gas fee provided. \n"
				logger.log("Invalid gas fee for Solana.")
				isValidForm = false
				return isValidForm
			}
			
			guard let amountInSOL = Decimal(string: tx.amount) else {
				errorMessage += "Invalid transaction amount provided. \n"
				logger.log("Invalid transaction amount for Solana.")
				isValidForm = false
				return isValidForm
			}
			
			let amountInLamports = amountInSOL * Decimal(1_000_000_000)
			
			let totalCostInLamports = amountInLamports + feeInLamports
			if totalCostInLamports > Decimal(walletBalanceInLamports) {
				errorMessage += "The combined amount and fee exceed your wallet's balance for Solana. Please adjust to proceed. \n"
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
}
