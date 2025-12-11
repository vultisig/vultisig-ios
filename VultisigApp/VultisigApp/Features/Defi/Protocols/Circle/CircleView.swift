//
//  CircleView.swift
//  VultisigApp
//
//  Created by Antigravity on 2025-12-11.
//

import SwiftUI
import SwiftData
import BigInt
import WalletCore
import VultisigCommonData

struct CircleView: View {
    let vault: Vault
    
    // Logic/State separation as requested
    @StateObject private var model = CircleViewModel()
    
    var body: some View {
        ZStack {
            Theme.colors.bgPrimary.ignoresSafeArea()
            
            VStack {
                if let address = vault.circleWalletAddress, !address.isEmpty {
                    CircleDashboardView(vault: vault, model: model)
                } else {
                    CircleSetupView(vault: vault, model: model)
                }
            }
        }
        .navigationTitle(NSLocalizedString("circleTitle", comment: "Circle"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - View Model (State Only)
final class CircleViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var error: Error?
    @Published var balance: Decimal = .zero
    @Published var apy: String = "0%"
    @Published var totalRewards: String = "0"
    
    // Logic is delegated to CircleViewLogic struct
    let logic = CircleViewLogic()
}

// MARK: - Logic (Methods)
struct CircleViewLogic {
    func createWallet(vault: Vault) async throws -> String {
        return try await CircleApiService.shared.createWallet(vaultPubkey: vault.pubKeyECDSA)
    }
    
    func fetchData(address: String) async throws -> (Decimal, CircleApiService.CircleYieldResponse) {
        async let balance = CircleApiService.shared.fetchBalance(address: address)
        async let yield = CircleApiService.shared.fetchYield(address: address)
        return try await (balance, yield)
    }
    
    func getWithdrawalPayload(vault: Vault, recipient: String, amount: BigInt) async throws -> KeysignPayload {
        // 1. Get Transaction Data from Backend
        // The backend `withdraw` endpoint returns the calldata to execute the withdrawal
        guard let ethAddress = vault.coins.first(where: { $0.chain == .ethereum })?.address else {
             throw CircleServiceError.invalidDetails
        }
        
        let tx = try await CircleApiService.shared.withdraw(
            walletAddress: vault.circleWalletAddress ?? "", // Should be handled before calling this if nil
            recipientAddress: recipient,
            amount: String(amount) // Convert BigInt to String
        )
        
        // 2. Fetch Nonce (EOA)
        let service = try EvmService.getService(forChain: .ethereum)
        let (_, _, nonce) = try await service.getGasInfo(fromAddress: ethAddress, mode: .normal)

        let gasLimit = CircleMSCAConfig.gasLimit
        let maxFeePerGas = BigInt(tx.maxFeePerGas) ?? BigInt(50000000000)
        let maxPriorityFeePerGas = BigInt(tx.maxPriorityFeePerGas) ?? BigInt(1500000000)
        
        // 3. Construct BlockChainSpecific
        let specific = BlockChainSpecific.Ethereum(
            maxFeePerGasWei: maxFeePerGas,
            priorityFeeWei: maxPriorityFeePerGas,
            nonce: Int64(nonce),
            gasLimit: gasLimit
        )
        
        let amountBigInt = BigInt(amount) ?? BigInt(0)
        
        let keysignMessage = try await CircleService.shared.getKeysignPayload(
            encryptionKeyHex: vault.hexChainCode,
            vault: vault,
            toAddress: tx.to, // Contract address
            amount: amountBigInt,
            memo: nil,
            fee: maxFeePerGas * gasLimit,
            chainSpecific: specific
        )
        
        guard let payload = keysignMessage.payload else {
            throw CircleServiceError.keysignError("Failed to generate keysign payload")
        }
        
        return payload
    }
}

// Localization keys to be added:
// "circleTitle" = "Circle";
