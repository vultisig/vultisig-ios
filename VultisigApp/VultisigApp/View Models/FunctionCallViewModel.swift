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
    
    func feesInReadable(tx: SendTransaction, vault: Vault) -> String {
        guard let nativeCoin = vault.nativeCoin(for: tx.coin) else { return .empty }
        let fee = nativeCoin.decimal(for: tx.gas)
        return RateProvider.shared.fiatBalanceString(value: fee, cryptoId: nativeCoin.cryptoId())
    }
    
    func memoDictionary(for txDict: ThreadSafeDictionary<String, String>) -> [String: String] {
        guard !txDict.allKeysInOrder().isEmpty else {
            return [String: String]()
        }
        
        let validKeys = txDict.allKeysInOrder().filter { key in
            guard let value = txDict.get(key) else { return false }
            return !value.isEmpty && value != "0" && value != "0.0"
        }
        
        var dict = [String: String]()
        validKeys.forEach { key in
            guard let value = txDict.get(key) else {
                return
            }
            dict[key.toFormattedTitleCase()] = value
        }
        
        return dict
    }
    
    func setRujiToken(to tx: SendTransaction, vault: Vault) {
        let rujiToken = vault.coins.first(where: { $0.chain == .thorChain && $0.ticker.uppercased() == "RUJI" })
        guard let rujiToken else { return }
        tx.coin = rujiToken
    }
    
    func setRuneToken(to tx: SendTransaction, vault: Vault) {
        let runeToken = vault.coins.first(where: { $0.chain == .thorChain && $0.isNativeToken })
        guard let runeToken else { return }
        tx.coin = runeToken
    }
    
    func setTcyToken(to tx: SendTransaction, vault: Vault) {
        let tcyToken = vault.coins.first(where: { $0.chain == .thorChain && $0.ticker.uppercased() == "TCY" })
        guard let tcyToken else { return }
        tx.coin = tcyToken
    }
}
