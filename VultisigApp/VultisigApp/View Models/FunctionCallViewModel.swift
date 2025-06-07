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
class FunctionCallViewModel: ObservableObject, TransferViewModel {
    @Published var isLoading = false
    @Published var isValidAddress = false
    @Published var isValidForm = true
    @Published var showAlert = false
    @Published var currentIndex = 1
    @Published var currentTitle = "function"
    @Published var priceRate = 0.0
    @Published var coinBalance: String = "0"
    @Published var errorMessage = ""
    @Published var hash: String? = nil
    @Published var approveHash: String? = nil

    let blockchainService = BlockChainService.shared
    private let fastVaultService = FastVaultService.shared
        
    private let mediator = Mediator.shared
    
    let totalViews = 5
    let titles = ["function", "verify", "pair", "keysign", "done"]
    
    let logger = Logger(subsystem: "deposit-input-details", category: "deposity")
    
    func loadGasInfoForSending(tx: SendTransaction) async{
        do {
            let chainSpecific = try await blockchainService.fetchSpecific(tx: tx)
            tx.gas = chainSpecific.gas
        } catch {
            print("error fetching data: \(error.localizedDescription)")
        }
    }
    
    func loadFastVault(tx: SendTransaction, vault: Vault) async {
        let isExist = await fastVaultService.exist(pubKeyECDSA: vault.pubKeyECDSA)
        let isLocalBackup = vault.localPartyID.lowercased().contains("server-")
        tx.isFastVault = isExist && !isLocalBackup
    }
    
    func validateAddress(tx: SendTransaction, address: String) {
        isValidAddress = AddressService.validateAddress(address: address, chain: tx.coin.chain)
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
        currentTitle = titles[currentIndex-1]
    }
}
