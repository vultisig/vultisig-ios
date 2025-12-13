//
//  CircleSetupView.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2025-12-11.
//

import SwiftUI

struct CircleSetupView: View {
    let vault: Vault
    @ObservedObject var model: CircleViewModel
    
    @State private var showInfoBanner = true
    
    var body: some View {
        ZStack {
            VaultMainScreenBackground()
            
            ScrollView {
                VStack(spacing: 24) {
                    // 2. Top Banner
                    topBanner
                    
                    // 3. Section Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString("circleSetupDeposited", comment: "Deposited"))
                            .font(.headline) // Tab-like style
                            .foregroundStyle(Theme.colors.textPrimary)
                        
                        Text(NSLocalizedString("circleSetupDepositDescription", comment: "Deposit your $USDC..."))
                            .font(.body)
                            .foregroundStyle(Theme.colors.textLight)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    
                    // 4. Info Banner
                    if showInfoBanner {
                        InfoBannerView(
                            description: NSLocalizedString("circleSetupInfoText", comment: "Funds remain..."),
                            type: .info,
                            leadingIcon: "info.circle", // Standard icon
                            onClose: {
                                withAnimation { showInfoBanner = false }
                            }
                        )
                        .padding(.horizontal, 16)
                    }
                    
                    // 5. Bottom Card & 6. Action Button
                    bottomCard
                }
                .padding(.vertical, 20)
            }
        }
        .navigationTitle("") // No title in navbar
        #if os(iOS)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackButton()
            }
        }
        #endif
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                NavigationBackButton()
            }
        }
        #endif
    }
    
    private var topBanner: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("circleSetupAccountTitle", comment: "Circle USDC Account"))
                    .font(.subheadline)
                    .bold()
                    .foregroundStyle(Theme.colors.textLight)
                
                Text("$1,240.50") // Placeholder as requested
                    .font(.system(size: 32, weight: .bold)) // Primary emphasis
                    .foregroundStyle(Theme.colors.textPrimary)
            }
            Spacer()
            // Decorative graphic
            Image(systemName: "circle.hexagongrid")
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.colors.primaryAccent1, Theme.colors.primaryAccent4],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .padding(24)
        .background(cardBackground)
        .padding(.horizontal, 16)
    }
    
    private var bottomCard: some View {
        VStack(spacing: 24) {
            HStack(spacing: 12) {
                Image("usdc") // Existing USDC asset
                    .resizable()
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("circleSetupUSDCDeposited", comment: "USDC deposited"))
                        .font(.caption)
                        .foregroundStyle(Theme.colors.textLight)
                    
                    Text("\(model.balance.formatted()) USDC")
                        .font(.title2)
                        .bold()
                        .foregroundStyle(Theme.colors.textPrimary)
                }
                Spacer()
            }
            
            // 6. Primary Action Button
            DefiButton(
                title: NSLocalizedString("circleSetupOpenAccount", comment: "Open Account"),
                icon: "arrow.right", // Standard forward action
                action: {
                    Task { await createWallet() }
                }
            )
        }
        .padding(24)
        .background(cardBackground)
        .padding(.horizontal, 16)
    }
    
    // Reused DeFi Card Style
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .inset(by: 0.5)
            .stroke(Color(hex: "34E6BF").opacity(0.17))
            .fill(
                LinearGradient(
                    stops: [
                        Gradient.Stop(color: Color(hex: "34E6BF"), location: 0.00),
                        Gradient.Stop(color: Color(red: 0.11, green: 0.5, blue: 0.42).opacity(0), location: 1.00),
                    ],
                    startPoint: UnitPoint(x: 0.5, y: 0),
                    endPoint: UnitPoint(x: 0.5, y: 1)
                ).opacity(0.09)
            )
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
