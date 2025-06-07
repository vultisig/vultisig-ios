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
    @Published var isHackedOrPhished = false
    @Published var showAlert = false
    @Published var isLoading = false
    @Published var errorMessage = ""
    
    @Published var utxo = BlockchairService.shared
    let blockChainService = BlockChainService.shared
    
    var isValidForm: Bool {
        return isAddressCorrect && isAmountCorrect && isHackedOrPhished
    }
    
    
    func validateForm(tx: SendTransaction, vault: Vault) async -> KeysignPayload? {
        if !isValidForm {
            self.errorMessage = "mustAgreeTermsError"
            showAlert = true
            isLoading = false
            return nil
        }
        
        var keysignPayload: KeysignPayload?
        
        // DEBUG: Print all tx properties
        print("=== SendTransaction Debug Info ===")
        print("Chain: \(tx.coin.chain)")
        print("ChainType: \(tx.coin.chainType)")
        print("Ticker: \(tx.coin.ticker)")
        print("Amount: \(tx.amount)")
        print("AmountInRaw: \(tx.amountInRaw)")
        print("ToAddress: \(tx.toAddress)")
        print("FromAddress: \(tx.fromAddress)")
        print("Gas: \(tx.gas)")
        print("Fee: \(tx.fee)")
        print("SendMaxAmount: \(tx.sendMaxAmount)")
        print("Coin.rawBalance: \(tx.coin.rawBalance)")
        print("Coin.isNativeToken: \(tx.coin.isNativeToken)")
        print("===================================")
        
        if tx.coin.chain.chainType == ChainType.UTXO {
            do {
                _ = try await utxo.fetchBlockchairData(coin: tx.coin)
            } catch {
                print("fail to fetch utxo data from blockchair , error:\(error.localizedDescription)")
            }
        }
        
        do {
            let chainSpecific = try await blockChainService.fetchSpecific(tx: tx)
            
            // DEBUG: Print chainSpecific properties
            print("=== ChainSpecific Debug Info ===")
            print("ChainSpecific: \(chainSpecific)")
            print("ChainSpecific.gas: \(chainSpecific.gas)")
            print("ChainSpecific.fee: \(chainSpecific.fee)")
            print("================================")
            
            keysignPayload = try await KeysignPayloadFactory().buildTransfer(
                coin: tx.coin,
                toAddress: tx.toAddress,
                amount: tx.amountInRaw,
                memo: tx.memo,
                chainSpecific: chainSpecific,
                vault: vault
            )
            
        } catch {
            print("=== KeysignPayloadFactory Error ===")
            print("Error: \(error)")
            print("Error description: \(error.localizedDescription)")
            print("===================================")
            self.errorMessage = error.localizedDescription
            showAlert = true
            isLoading = false
            return nil
        }
        return keysignPayload
    }
}
