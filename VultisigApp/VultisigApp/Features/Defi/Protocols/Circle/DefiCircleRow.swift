//
//  DefiCircleRow.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2025-12-11.
//

import SwiftUI

struct DefiCircleRow: View {
    let vault: Vault
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    @State private var circleBalance: Decimal? = nil
    @State private var isLoading: Bool = true
    @State private var hasError: Bool = false
    
    private let logic = CircleViewLogic()
    
    var body: some View {
        HStack {
            HStack(spacing: 12) {
                // Circle Logo
                Image("circle-logo")
                    .resizable()
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Theme.colors.borderLight, lineWidth: 1))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("circleTitle", comment: "Circle"))
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                    
                    if let address = vault.circleWalletAddress {
                        Text(address.truncatedMiddle)
                            .font(Theme.fonts.caption12)
                            .foregroundStyle(Theme.colors.textTertiary)
                    } else {
                        Text(NSLocalizedString("circleRowCreateWallet", comment: "Create Wallet"))
                            .font(Theme.fonts.caption12)
                            .foregroundStyle(Theme.colors.textTertiary)
                    }
                }
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                rightSideContent
                Icon(named: "chevron-right-small", color: Theme.colors.textPrimary, size: 16)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, CircleConstants.Design.horizontalPadding)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(10)
        .buttonStyle(.plain)
        .task {
            await loadBalance()
        }
    }
    
    @ViewBuilder
    private var rightSideContent: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if vault.circleWalletAddress != nil {
                // Wallet exists - show balance or loading/error state
                if isLoading {
                    // Loading state
                    Text("...")
                        .font(Theme.fonts.priceBodyS)
                        .foregroundStyle(Theme.colors.textPrimary)
                    Text(NSLocalizedString("circleRowYieldAccount", comment: "Yield Account"))
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                } else if hasError {
                    // Error state - show dash
                    Text("-- USDC")
                        .font(Theme.fonts.priceBodyS)
                        .foregroundStyle(Theme.colors.textPrimary)
                    Text(NSLocalizedString("circleRowYieldAccount", comment: "Yield Account"))
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                } else if let balance = circleBalance, balance > 0 {
                    // Has positive balance - show amount
                    Text("\(balance.formatted()) USDC")
                        .font(Theme.fonts.priceBodyS)
                        .foregroundStyle(Theme.colors.textPrimary)
                    Text("$\(balance.formatted())")
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                } else {
                    // Balance is zero or nil - show Yield Account
                    Text("0 USDC")
                        .font(Theme.fonts.priceBodyS)
                        .foregroundStyle(Theme.colors.textPrimary)
                    Text(NSLocalizedString("circleRowYieldAccount", comment: "Yield Account"))
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                }
            } else {
                // No wallet - show Get Started
                Text(NSLocalizedString("circleRowGetStarted", comment: "Get Started"))
                    .font(Theme.fonts.priceBodyS)
                    .foregroundStyle(Theme.colors.primaryAccent4)
            }
        }
    }
    
    private func loadBalance() async {
        guard let address = vault.circleWalletAddress else {
            await MainActor.run {
                isLoading = false
            }
            return
        }
        
        do {
            let (usdcBalance, _) = try await logic.fetchData(address: address, vault: vault)
            await MainActor.run {
                circleBalance = usdcBalance
                isLoading = false
                hasError = false
            }
        } catch {
            print("DefiCircleRow: Error loading balance: \(error.localizedDescription)")
            await MainActor.run {
                isLoading = false
                hasError = true
            }
        }
    }
}
