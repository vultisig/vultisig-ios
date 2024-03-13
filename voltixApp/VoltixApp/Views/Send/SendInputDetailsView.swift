	//
	//  VoltixApp
	//
	//  Created by Enrique Souza Soares
	//
	// TODO: Create an abstraction, so we dont keep using if coin...
	// I will do it after the MVP
	//
import BigInt
import CodeScanner
import Combine
import OSLog
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WalletCore

private class DebounceHelper {
	static let shared = DebounceHelper()
	private var workItem: DispatchWorkItem?
	
	func debounce(delay: TimeInterval = 0.5, action: @escaping () -> Void) {
		workItem?.cancel()
		let task = DispatchWorkItem { action() }
		workItem = task
		DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
	}
}

private let logger = Logger(subsystem: "send-input-details", category: "transaction")
struct SendInputDetailsView: View {
	enum Field: Hashable {
		case toAddress
		case amount
		case amountInUSD
		case memo
		case gas
	}
	
	@EnvironmentObject var appState: ApplicationState
	@Binding var presentationStack: [CurrentScreen]
	@StateObject var uxto: UnspentOutputsService = .init()
	@StateObject var uxtoLtc: LitecoinUnspentOutputsService = .init()
	@StateObject var eth: EthplorerAPIService = .init()
	@StateObject var web3Service = Web3Service()
	@StateObject var cryptoPrice = CryptoPriceService.shared
	@StateObject var thor: ThorchainService = .shared
	@StateObject var sol: SolanaService = SolanaService.shared
	@ObservedObject var tx: SendTransaction
	@State private var isShowingScanner = false
	@State private var isValidAddress = false
	@State private var formErrorMessages = ""
	@State private var isValidForm = true
	@State private var keyboardOffset: CGFloat = 0
	@State private var amountInUsd: Double = 0.0
	@State private var coinBalance: String = "0"
	@State private var isCollapsed = true
	@State private var isLoading = false
	@State private var priceRate = 0.0
	
	@FocusState private var focusedField: Field?
	
	var body: some View {
		ScrollView {
			VStack(alignment: .leading) {
				if !isLoading {
					Group {
						HStack {
							Text(tx.coin.ticker.uppercased())
								.font(.body18MenloBold)
							
							Spacer()
							
							Text(coinBalance).font(
								.system(size: 18))
						}
					}.padding(.vertical)
					Group {
						VStack(alignment: .leading) {
							Text("From")
								.font(.body18MenloBold)
								.padding(.bottom)
							Text(tx.fromAddress)
						}
					}.padding(.vertical)
					Group {
						HStack {
							Text("To:")
								.font(.body18MenloBold)
							Text(isValidAddress ? "" : "*")
								.font(.body18MenloBold)
								.foregroundColor(.red)
							Spacer()
							Button("", systemImage: "doc.on.clipboard") {
								if let clipboardContent = UIPasteboard.general.string {
									tx.toAddress = clipboardContent
									validateAddress(clipboardContent)
								}
							}
							.buttonStyle(PlainButtonStyle())
							
							Button("", systemImage: "camera") {
								self.isShowingScanner = true
							}
							.buttonStyle(PlainButtonStyle())
							.sheet(
								isPresented: self.$isShowingScanner,
								content: {
									CodeScannerView(codeTypes: [.qr], completion: self.handleScan)
								}
							)
						}
						TextField("To Address", text: Binding<String>(
							get: { self.tx.toAddress },
							set: { newValue in
								self.tx.toAddress = newValue
								DebounceHelper.shared.debounce {
									validateAddress(newValue)
								}
							}
						))
						.textInputAutocapitalization(.never)
						.disableAutocorrection(true)
						.keyboardType(.default)
						.textContentType(.oneTimeCode)
						.focused($focusedField, equals: .toAddress)
						.padding()
						.background(Color.gray.opacity(0.5))
						.cornerRadius(10)
						
					}.padding(.bottom)
					Group {
						HStack {
							VStack(alignment: .leading) {
								Text("\(tx.coin.ticker.uppercased()):")
									.font(.body18MenloBold)
								
								HStack {
									TextField("Amount", text: Binding<String>(
										get: { self.tx.amount },
										set: { newValue in
											self.tx.amount = newValue
											DebounceHelper.shared.debounce {
												self.convertToUSD(newValue: newValue)
											}
										}
									))
									.textInputAutocapitalization(.never)
									.keyboardType(.decimalPad)
									.textContentType(.oneTimeCode)
									.disableAutocorrection(true)
									.focused($focusedField, equals: .amount)
									.padding()
									.background(Color.gray.opacity(0.5))
									.cornerRadius(10)
								}
							}
							VStack(alignment: .leading) {
								Text("USD:")
									.font(.body18MenloBold)
								
								HStack {
									TextField("USD", text: Binding<String>(
										get: { self.tx.amountInUSD },
										set: { newValue in
											self.tx.amountInUSD = newValue
											DebounceHelper.shared.debounce {
												self.convertUSDToCoin(newValue: newValue)
											}
										}
									))
									.keyboardType(.decimalPad)
									.textContentType(.oneTimeCode)
									.disableAutocorrection(true)
									.focused($focusedField, equals: .amountInUSD)
									.padding()
									.background(Color.gray.opacity(0.5))
									.cornerRadius(10)
									
									Button(action: {
										setMaxValues()
									}) {
										Text("MAX")
											.font(.body18MenloBold)
											.foregroundColor(Color.primary)
									}
								}
							}
						}
						
					}.padding(.bottom)
					
					Group {
						Text("Memo:")
							.font(.body18MenloBold)
						TextField("Memo", text: $tx.memo)
							.textInputAutocapitalization(.never)
							.disableAutocorrection(true)
							.keyboardType(.default)
							.textContentType(.oneTimeCode)
							.focused($focusedField, equals: .memo)
							.padding()
							.background(Color.gray.opacity(0.5))
							.cornerRadius(10)
					}.padding(.bottom)
					
					Group {
						Text("Fee:")
							.font(.body18MenloBold)
						HStack {
							TextField("Fee", text: $tx.gas)
								.keyboardType(.decimalPad)
								.textContentType(.oneTimeCode)
								.disableAutocorrection(true)
								.focused($focusedField, equals: .gas)
								.padding()
								.background(Color.gray.opacity(0.5))
								.cornerRadius(10)
							Spacer()
							Text("\($tx.gas.wrappedValue) \(tx.coin.feeUnit ?? "NO UNIT")")
								.font(.body18MenloBold)
						}
					}.padding(.bottom)
					Text(isValidForm ? "" : formErrorMessages)
						.font(.body13MenloBold)
						.foregroundColor(.red)
						.padding()
					Group {
						BottomBar(
							content: "CONTINUE",
							onClick: {
								if validateForm() {
									self.presentationStack.append(.sendVerifyScreen(tx))
								}
							}
						)
					}
				}
			}
			.overlay(
				Group {
					if isLoading {
						ProgressView()
							.progressViewStyle(CircularProgressViewStyle(tint: .blue))
							.frame(maxWidth: .infinity, maxHeight: .infinity)
							.background(Color.black.opacity(0.45))
							.edgesIgnoringSafeArea(.all)
					}
				}
			)
			.onAppear {
				reloadTransactions()
			}
			.navigationBarBackButtonHidden()
			.navigationTitle("SEND")
			.modifier(InlineNavigationBarTitleModifier())
			.toolbar {
				ToolbarItem(placement: .navigationBarLeading) {
					NavigationButtons.backButton(presentationStack: $presentationStack)
				}
				ToolbarItem(placement: .navigationBarTrailing) {
					NavigationButtons.refreshButton(action: {
						reloadTransactions()
					})
				}
			}
		}.padding()
	}
	
	private func convertUSDToCoin(newValue: String) {
		if let newValueDouble = Double(newValue) {
			var newCoinAmount = ""
			
			if	tx.coin.chain.name.lowercased() == Chain.Bitcoin.name.lowercased() ||
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
	
	private func convertToUSD(newValue: String) {
		if let newValueDouble = Double(newValue) {
			var newValueUSD = ""
			
			if 	tx.coin.chain.name.lowercased() == Chain.Bitcoin.name.lowercased() ||
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
	
	private func validateAddress(_ address: String) {
		if tx.coin.ticker.uppercased() == Chain.Bitcoin.ticker.uppercased() {
			isValidAddress = CoinType.bitcoin.validate(address: address)
		} else if tx.coin.ticker.uppercased() == Chain.Litecoin.ticker.uppercased() {
			isValidAddress = CoinType.litecoin.validate(address: address)
		} else if tx.coin.chain.name.lowercased() == Chain.Ethereum.name.lowercased() {
			isValidAddress = CoinType.ethereum.validate(address: address)
		} else if tx.coin.chain.name.lowercased() == Chain.THORChain.name.lowercased() {
			isValidAddress = CoinType.thorchain.validate(address: address)
		} else if tx.coin.chain.name.lowercased() == Chain.Solana.name.lowercased() {
			isValidAddress = CoinType.solana.validate(address: address)
		}
	}
	
	private func validateForm() -> Bool {
			// Reset validation state at the beginning
		formErrorMessages = ""
		isValidForm = true
		
			// Validate the "To" address
		if !isValidAddress {
			formErrorMessages += "Please enter a valid address. \n"
			logger.log("Invalid address.")
			isValidForm = false
		}
		
		let amount = tx.amountDecimal
		let gasFee = tx.gasDecimal
		
		if amount <= 0 {
			formErrorMessages += "Amount must be a positive number. Please correct your entry. \n"
			logger.log("Invalid or non-positive amount.")
			isValidForm = false
			return isValidForm
		}
		
		if gasFee <= 0 {
			formErrorMessages += "Fee must be a non-negative number. Please correct your entry. \n"
			logger.log("Invalid or negative fee.")
			isValidForm = false
			return isValidForm
		}
		
		
		if tx.coin.chain.name.lowercased() == Chain.Bitcoin.name.lowercased() {
			let walletBalanceInSats = uxto.walletData?.balance ?? 0
			let totalTransactionCostInSats = tx.amountInSats + tx.feeInSats
			print("Total transaction cost: \(totalTransactionCostInSats)")
			
			if totalTransactionCostInSats > walletBalanceInSats {
				formErrorMessages += "The combined amount and fee exceed your wallet's balance. Please adjust to proceed. \n"
				logger.log("Total transaction cost exceeds wallet balance.")
				isValidForm = false
			}
			
		} else if tx.coin.chain.name.lowercased() == Chain.Litecoin.name.lowercased() {
			let walletBalanceInSats = uxtoLtc.walletData?.balance ?? 0
			let totalTransactionCostInSats = tx.amountInSats + tx.feeInSats
			print("Total transaction cost: \(totalTransactionCostInSats)")
			
			if totalTransactionCostInSats > walletBalanceInSats {
				formErrorMessages += "The combined amount and fee exceed your wallet's balance. Please adjust to proceed. \n"
				logger.log("Total transaction cost exceeds wallet balance.")
				isValidForm = false
			}
			
		} else if tx.coin.chain.name.lowercased() == Chain.Ethereum.name.lowercased() {
			let ethBalanceInWei = Int(eth.addressInfo?.ETH.rawBalance ?? "0") ?? 0 // it is in WEI
			
			if tx.coin.ticker.uppercased() == "ETH" {
				if tx.totalEthTransactionCostWei > ethBalanceInWei {
					formErrorMessages += "The combined amount and fee exceed your wallet's balance. Please adjust to proceed. \n"
					logger.log("Total transaction cost exceeds wallet balance.")
					isValidForm = false
				}
				
			} else {
				if let tokenInfo = eth.addressInfo?.tokens?.first(where: { $0.tokenInfo.symbol == tx.coin.ticker.uppercased() }) {
					print("tx.feeInWei \(tx.feeInWei)")
					print("ethBalanceInWei \(ethBalanceInWei)")
					
					print("has eth to pay the fee?  \(tx.feeInWei > ethBalanceInWei)")
					
					if tx.feeInWei > ethBalanceInWei {
						formErrorMessages += "You must have ETH in to send any TOKEN, so you can pay the fees. \n"
						logger.log("You must have ETH in to send any TOKEN, so you can pay the fees. \n")
						isValidForm = false
					}
					
					let tokenBalance = Int(tokenInfo.rawBalance) ?? 0
					
					if tx.amountInTokenWei > tokenBalance {
						formErrorMessages += "Total transaction cost exceeds wallet balance. \n"
						logger.log("Total transaction cost exceeds wallet balance.")
						isValidForm = false
					}
				}
			}
		} else if tx.coin.chain.name.lowercased() == Chain.THORChain.name.lowercased() {
			
		} else if tx.coin.chain.name.lowercased() == Chain.Solana.name.lowercased() {
			
			guard let walletBalanceInLamports = sol.balance else {
				formErrorMessages += "Wallet balance is not available. \n"
				logger.log("Wallet balance is not available for Solana.")
				isValidForm = false
				return isValidForm
			}
			
			let optionalGas: String? = tx.gas
			guard let feeStr = optionalGas, let feeInLamports = Decimal(string: feeStr) else {
				formErrorMessages += "Invalid gas fee provided. \n"
				logger.log("Invalid gas fee for Solana.")
				isValidForm = false
				return isValidForm
			}
			
			guard let amountInSOL = Decimal(string: tx.amount) else {
				formErrorMessages += "Invalid transaction amount provided. \n"
				logger.log("Invalid transaction amount for Solana.")
				isValidForm = false
				return isValidForm
			}
			
			let amountInLamports = amountInSOL * Decimal(1_000_000_000)
			
			let totalCostInLamports = amountInLamports + feeInLamports
			if totalCostInLamports > Decimal(walletBalanceInLamports) {
				formErrorMessages += "The combined amount and fee exceed your wallet's balance for Solana. Please adjust to proceed. \n"
				logger.log("Total transaction cost exceeds wallet balance for Solana.")
				isValidForm = false
			}
		}
		
		return isValidForm
	}
	
	private func setMaxValues() {
		if tx.coin.chain.name.lowercased() == Chain.Bitcoin.name.lowercased() {
			let rate = priceRate
			if let walletData = uxto.walletData {
				tx.amount = walletData.balanceInBTC
				tx.amountInUSD = String(format: "%.2f", walletData.balanceDecimal * rate)
			}
		}
		if tx.coin.chain.name.lowercased() == Chain.Litecoin.name.lowercased() {
			let rate = priceRate
			if let walletData = uxtoLtc.walletData {
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
	
	private func updateState() {
		isLoading = true
			// TODO: move this logic into an abstraction
		
		if let priceRateUsd = cryptoPrice.cryptoPrices?.prices[tx.coin.chain.name.lowercased()]?["usd"] {
			priceRate = priceRateUsd
		}
		
		if tx.coin.chain.name.lowercased() == Chain.Bitcoin.name.lowercased() {
			coinBalance = uxto.walletData?.balanceInBTC ?? "0"
		} else if tx.coin.chain.name.lowercased() == Chain.Litecoin.name.lowercased() {
			coinBalance = uxtoLtc.walletData?.balanceInLTC ?? "0"
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
	
	private func reloadTransactions() {
			// TODO: move this logic into an abstraction
			// ETH gets the price from other sourcers.
		Task {
			isLoading = true
			
			await cryptoPrice.fetchCryptoPrices(for: "bitcoin,litecoin,thorchain,solana", for: "usd")
			
			if tx.coin.chain.name.lowercased() == Chain.Bitcoin.name.lowercased() {
				await uxto.fetchUnspentOutputs(for: tx.fromAddress)
			} else if tx.coin.chain.name.lowercased() == Chain.Litecoin.name.lowercased() {
				await uxtoLtc.fetchLitecoinUnspentOutputs(for: tx.fromAddress)
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
				updateState()
				isLoading = false
			}
		}
	}
	
	private func handleScan(result: Result<ScanResult, ScanError>) {
		switch result {
			case .success(let result):
				let qrCodeResult = result.string
				tx.parseCryptoURI(qrCodeResult)
				isShowingScanner = false
			case .failure(let err):
				logger.error("fail to scan QR code,error:\(err.localizedDescription)")
		}
	}
}
