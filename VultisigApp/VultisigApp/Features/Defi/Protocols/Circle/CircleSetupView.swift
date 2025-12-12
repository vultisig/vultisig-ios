//
//  CircleSetupView.swift
//  VultisigApp
//
//  Created by Antigravity on 2025-12-11.
//

import SwiftUI

struct CircleSetupView: View {
    let vault: Vault
    @ObservedObject var model: CircleViewModel
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "circle.hexagongrid")
                .font(.system(size: 80))
                .foregroundStyle(LinearGradient.primaryGradient)
                .symbolEffect(.pulse, isActive: true)
                .padding(.bottom, 20)
            
            Text(NSLocalizedString("circleSetupTitle", comment: "Circle Programmable Wallet"))
                .font(.title)
                .bold()
                .foregroundStyle(Theme.colors.textPrimary)
            
            Text(NSLocalizedString("circleSetupDescription", comment: "Earn yield..."))
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.colors.textLight)
                .padding(.horizontal, 32)
            
            Spacer()
            
            PrimaryButton(title: NSLocalizedString("circleSetupCreateAccount", comment: "Create Account")) {
                Task {
                    await createWallet()
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 30)
            
            Spacer()
                .frame(height: 20)
        }
        .padding()
        .background(Theme.colors.bgPrimary)
    }
    
    private func createWallet() async {
        print("CircleSetupView: Starting createWallet flow")
        await MainActor.run { model.isLoading = true }
        do {
            print("CircleSetupView: Calling model.logic.createWallet with vault: \(vault.pubKeyECDSA)")
            let newAddress = try await model.logic.createWallet(vault: vault)
            print("CircleSetupView: Wallet created successfully with address: \(newAddress)")
            await MainActor.run {
                vault.circleWalletAddress = newAddress
                model.isLoading = false
            }
        } catch {
            print("CircleSetupView: Failed to create wallet. Error: \(error)")
            await MainActor.run {
                model.error = error
                model.isLoading = false
            }
        }
    }
}

// Localization keys to be added:
// "circleSetupTitle" = "Circle Programmable Wallet";
// "circleSetupDescription" = "Earn yield on your USDC with a smart contract account controlled by your vault.";
// "circleSetupCreateAccount" = "Create Account";
