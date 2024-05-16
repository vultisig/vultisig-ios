//
//  DepositViewModel.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 14/05/24.
//

import Foundation
import SwiftUI
import BigInt
import OSLog
import WalletCore
import Mediator

@MainActor
class TransactionMemoViewModel: ObservableObject, TransferViewModel {
    @Published var isLoading = false
    @Published var isValidAddress = false
    @Published var isValidForm = true
    @Published var showAlert = false
    @Published var currentIndex = 1
    @Published var currentTitle = "deposit"
    @Published var priceRate = 0.0
    @Published var coinBalance: String = "0"
    @Published var errorMessage = ""
    @Published var hash: String? = nil
    @Published var thor = ThorchainService.shared
    @Published var sol: SolanaService = SolanaService.shared
    @Published var sui: SuiService = SuiService.shared
    @Published var cryptoPrice = CryptoPriceService.shared
    @Published var utxo = BlockchairService.shared
    let maya = MayachainService.shared
    let atom = GaiaService.shared
    let kujira = KujiraService.shared
    let blockchainService = BlockChainService.shared
    
    private let mediator = Mediator.shared
    
    let totalViews = 5
    let titles = ["deposit", "verify", "pair", "keysign", "done"]
    
    let logger = Logger(subsystem: "deposit-input-details", category: "deposity")
    
    func loadGasInfoForSending(tx: SendTransaction) async{
        do {
            let chainSpecific = try await blockchainService.fetchSpecific(for: tx.coin, sendMaxAmount: false)
            tx.gas = chainSpecific.gas.description
        } catch {
            print("error fetching data: \(error.localizedDescription)")
        }
    }
    
    func validateAddress(tx: SendTransaction, address: String) {
        if tx.coin.chain == .mayaChain {
            isValidAddress = AnyAddress.isValidBech32(string: address, coin: .thorchain, hrp: "maya")
            return
        }
        isValidAddress = tx.coin.coinType.validate(address: address)
    }
    
    func validateForm(tx: SendTransaction) async -> Bool {
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
        
        if tx.isAmountExceeded {
            
            errorMessage = "walletBalanceExceededError"
            showAlert = true
            logger.log("Total transaction cost exceeds wallet balance.")
            isValidForm = false
            
        }
        
        let hasEnoughNativeTokensToPayTheFees = await tx.hasEnoughNativeTokensToPayTheFees()
        if !hasEnoughNativeTokensToPayTheFees {
            
            errorMessage = "walletBalanceExceededError"
            showAlert = true
            logger.log("You must have enough Native Tokens (Eg. ETH) to pay the fees.")
            isValidForm = false
            
        }
        
        return isValidForm
    }
    
    func setHash(_ hash: String) {
        self.hash = hash
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
    
    func handleBackTap() {
        currentIndex-=1
    }
}
