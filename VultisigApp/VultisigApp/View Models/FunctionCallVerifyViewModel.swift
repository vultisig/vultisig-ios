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
                
                // Fetch inbound addresses to get correct vault address
                let inboundAddresses = await ThorchainService.shared.fetchThorchainInboundAddress()
                let chainName = getInboundChainName(for: tx.coin.chain)
                
                guard let inbound = inboundAddresses.first(where: { $0.chain.uppercased() == chainName.uppercased() }) else {
                    print("FunctionCallVerifyViewModel: No inbound address found for chain \(chainName)")
                    return nil
                }
                
                // For ERC20 tokens, we need both vault (inbound) and router addresses
                let vaultAddress: String
                let routerAddress: String?
                
                if tx.coin.shouldApprove { // ERC20 tokens
                    // For ERC20: vault = inbound address, router = router address
                    vaultAddress = inbound.address // Asgard vault address
                    routerAddress = inbound.router // Router contract address
                } else { // Native tokens
                    // For native tokens: vault = inbound address, no router needed
                    vaultAddress = inbound.address // Asgard vault address
                    routerAddress = nil
                }
                
                let thorchainSwapPayload = THORChainSwapPayload(
                    fromAddress: tx.fromAddress,
                    fromCoin: tx.coin,
                    toCoin: tx.coin, // For LP, we're not swapping to a different coin
                    vaultAddress: vaultAddress,
                    routerAddress: routerAddress,
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
    
    private func getInboundChainName(for chain: Chain) -> String {
        // Map internal chain names to THORChain inbound address chain names
        switch chain {
        case .bitcoin:
            return "BTC"
        case .ethereum:
            return "ETH"
        case .avalanche:
            return "AVAX"
        case .bscChain:
            return "BSC"
        case .arbitrum:
            return "ARB"
        case .base:
            return "BASE"
        case .optimism:
            return "OP"
        case .polygon:
            return "MATIC"
        case .litecoin:
            return "LTC"
        case .bitcoinCash:
            return "BCH"
        case .dogecoin:
            return "DOGE"
        case .gaiaChain:
            return "GAIA"
        case .thorChain:
            return "THOR"
        default:
            // For unknown chains, use the chain's swapAsset
            return chain.swapAsset.uppercased()
        }
    }
}
