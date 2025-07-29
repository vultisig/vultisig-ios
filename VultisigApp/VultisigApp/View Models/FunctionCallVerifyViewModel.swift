//
//  DepositVerifyViewModel.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 14/05/24.
//

import Foundation
import SwiftUI
import BigInt
import WalletCore

@MainActor
class FunctionCallVerifyViewModel: ObservableObject {
    @Published var showAlert = false
    @Published var isLoading = false
    @Published var errorMessage = ""
    
    // General
    @Published var isAddressCorrect = false
    @Published var isAmountCorrect = false
    @Published var isHackedOrPhished = false
    
    let blockChainService = BlockChainService.shared
    
    func createKeysignPayload(tx: SendTransaction, vault: Vault) async -> KeysignPayload? {
        
        var keysignPayload: KeysignPayload?
        
        do {
            let chainSpecific = try await blockChainService.fetchSpecific(tx: tx)
            
            let keysignPayloadFactory = KeysignPayloadFactory()
            
            // Check if this is an AddThorLP transaction that requires ERC20 approval
            var approvePayload: ERC20ApprovePayload?
            var swapPayload: SwapPayload?
            
            if !tx.memoFunctionDictionary.allItems().isEmpty,
               let _ = tx.memoFunctionDictionary.get("pool") { // This indicates it's an AddThorLP transaction
                
                // For THORChain LP, create a THORChain swap payload
                let expirationTime = Date().addingTimeInterval(60 * 15) // 15 minutes
                let thorchainSwapPayload = THORChainSwapPayload(
                    fromAddress: tx.fromAddress,
                    fromCoin: tx.coin,
                    toCoin: tx.coin, // For LP, we're not swapping to a different coin
                    vaultAddress: tx.toAddress,
                    routerAddress: tx.toAddress,
                    fromAmount: tx.amountInRaw,
                    toAmountDecimal: tx.coin.decimal(for: tx.amountInRaw), // Convert BigInt to Decimal
                    toAmountLimit: "",
                    streamingInterval: "",
                    streamingQuantity: "",
                    expirationTime: UInt64(expirationTime.timeIntervalSince1970),
                    isAffiliate: false
                )
                swapPayload = .thorchain(thorchainSwapPayload)
                
                // Check if the coin requires approval (ERC20 tokens)
                if tx.coin.shouldApprove && !tx.toAddress.isEmpty {
                    approvePayload = ERC20ApprovePayload(
                        amount: tx.amountInRaw,
                        spender: tx.toAddress
                    )
                    print("FunctionCallVerifyViewModel: Created ERC20 approval payload for \(tx.coin.ticker) to spender \(tx.toAddress)")
                }
            }
            
            keysignPayload = try await keysignPayloadFactory.buildTransfer(coin: tx.coin,
                                                                           toAddress: tx.toAddress,
                                                                           amount: tx.amountInRaw,
                                                                           memo: tx.memo,
                                                                           chainSpecific: chainSpecific,
                                                                           swapPayload: swapPayload,
                                                                           approvePayload: approvePayload,
                                                                           vault: vault)
        } catch {
            switch error {
            case KeysignPayloadFactory.Errors.notEnoughBalanceError:
                self.errorMessage = "notEnoughBalanceError"
            case KeysignPayloadFactory.Errors.failToGetSequenceNo:
                self.errorMessage = "failToGetSequenceNo"
            case KeysignPayloadFactory.Errors.failToGetAccountNumber:
                self.errorMessage = "failToGetAccountNumber"
            case KeysignPayloadFactory.Errors.failToGetRecentBlockHash:
                self.errorMessage = "failToGetRecentBlockHash"
            default:
                self.errorMessage = error.localizedDescription
            }
            showAlert = true
            isLoading = false
            return nil
        }
        return keysignPayload
    }
}
