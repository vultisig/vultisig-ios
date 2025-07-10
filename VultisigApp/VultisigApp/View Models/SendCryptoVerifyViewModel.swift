//
//  SendCryptoVerifyViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-19.
//

import SwiftUI
import BigInt
import WalletCore

@MainActor
class SendCryptoVerifyViewModel: ObservableObject {
    
    @Published var isAddressCorrect = false
    @Published var isAmountCorrect = false
    @Published var showAlert = false
    @Published var isLoading = false
    @Published var errorMessage = ""
    
    @Published var securityScanViewModel = SecurityScanViewModel()
    @Published var showSecurityScan = false
    
    @Published var utxo = BlockchairService.shared
    let blockChainService = BlockChainService.shared
    
    var isValidForm: Bool {
        return isAddressCorrect && isAmountCorrect
    }
    
    
    func validateForm(tx: SendTransaction, vault: Vault) async -> KeysignPayload? {
        if !isValidForm {
            self.errorMessage = "mustAgreeTermsError"
            showAlert = true
            isLoading = false
            return nil
        }
        
        var keysignPayload: KeysignPayload?
        
        if tx.coin.chain.chainType == ChainType.UTXO {
            do {
                _ = try await utxo.fetchBlockchairData(coin: tx.coin)
            } catch {
                print("fail to fetch utxo data from blockchair , error:\(error.localizedDescription)")
            }
        }
        
        do {
            let chainSpecific = try await blockChainService.fetchSpecific(tx: tx)
            
            keysignPayload = try await KeysignPayloadFactory().buildTransfer(
                coin: tx.coin,
                toAddress: tx.toAddress,
                amount: tx.amountInRaw,
                memo: tx.memo,
                chainSpecific: chainSpecific,
                vault: vault
            )
            
        } catch {
            self.errorMessage = error.localizedDescription
            showAlert = true
            isLoading = false
            return nil
        }
        return keysignPayload
    }
    
    func performSecurityScan(tx: SendTransaction, vault: Vault) async {
        // Check if security scanning is available for this chain
        guard securityScanViewModel.isScanningAvailable(for: tx.coin.chain) else {
            print("Security scanning not available for chain: \(tx.coin.chain.name)")
            showSecurityScan = false
            return
        }
        
        // For Bitcoin/UTXO chains, fetch UTXOs first to enable proper scanning
        if tx.coin.chain.chainType == .UTXO {
            do {
                // Fetch UTXOs if not already fetched
                _ = try await utxo.fetchBlockchairData(coin: tx.coin)
                
                // Create a temporary keysign payload with UTXOs for scanning
                let chainSpecific = try await blockChainService.fetchSpecific(tx: tx)
                
                print("Creating keysign payload for Bitcoin security scan:")
                print("Coin: \(tx.coin.ticker)")
                print("To Address: \(tx.toAddress)")
                print("Amount (raw): \(tx.amountInRaw)")
                print("Amount (display): \(tx.amount)")
                
                let keysignPayload = try await KeysignPayloadFactory().buildTransfer(
                    coin: tx.coin,
                    toAddress: tx.toAddress,
                    amount: tx.amountInRaw,
                    memo: tx.memo,
                    chainSpecific: chainSpecific,
                    vault: vault
                )
                
                print("Keysign payload created with \(keysignPayload.utxos.count) UTXOs")
                
                // Scan using the keysign payload which has UTXOs
                await securityScanViewModel.scanTransaction(from: keysignPayload, vault: vault)
                showSecurityScan = true
                return
            } catch {
                print("Failed to fetch UTXOs for security scan: \(error)")
                // Fall back to regular scanning without UTXOs
            }
        }
        
        // For non-UTXO chains, use the regular flow
        await securityScanViewModel.scanTransaction(from: tx)
        showSecurityScan = true
    }
}
