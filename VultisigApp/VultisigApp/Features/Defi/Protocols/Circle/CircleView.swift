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
        print("CircleViewLogic: createWallet called for vault pubKey: \(vault.pubKeyECDSA)")
        return try await CircleApiService.shared.createWallet(vaultPubkey: vault.pubKeyECDSA)
    }
    
    func fetchData(address: String) async throws -> (Decimal, CircleApiService.CircleYieldResponse) {
        print("CircleViewLogic: fetchData called for address: \(address)")
        // Stub: The proxy doesn't support balance/yield. 
        // Future: Implement EVM RPC calls here.
        return (.zero, CircleApiService.CircleYieldResponse(apy: "0", totalRewards: "0", currentRewards: "0"))
    }
    
    func getWithdrawalPayload(vault: Vault, recipient: String, amount: BigInt) async throws -> KeysignPayload {
        print("CircleViewLogic: getWithdrawalPayload called.")
        throw CircleServiceError.keysignError("Withdrawal not implemented (Requires on-chain logic)")
    }
}

// Local definitions or extensions can go here if needed
