//
//  DefiTronRow.swift
//  VultisigApp
//
//  Created for TRON Freeze/Unfreeze integration
//

import SwiftUI

struct DefiTronRow: View {
    let vault: Vault
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    @State private var frozenBalance: Decimal? = nil
    @State private var isLoading: Bool = true
    @State private var hasError: Bool = false
    
    private let logic = TronViewLogic()
    
    var body: some View {
        HStack {
            HStack(spacing: 12) {
                // TRON Logo
                Image("tron-logo")
                    .resizable()
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Theme.colors.borderLight, lineWidth: 1))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("tronTitle", comment: "TRON Staking"))
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                    
                    if let trxCoin = TronViewLogic.getTrxCoin(vault: vault) {
                        Text(trxCoin.address.truncatedMiddle)
                            .font(Theme.fonts.caption12)
                            .foregroundStyle(Theme.colors.textTertiary)
                    } else {
                        Text(NSLocalizedString("tronRowAddTRX", comment: "Add TRX"))
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
        .padding(.horizontal, TronConstants.Design.horizontalPadding)
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
            if TronViewLogic.getTrxCoin(vault: vault) != nil {
                // TRX exists - show balance or loading/error state
                if isLoading {
                    // Loading state
                    Text("...")
                        .font(Theme.fonts.priceBodyS)
                        .foregroundStyle(Theme.colors.textPrimary)
                    Text(NSLocalizedString("tronRowFrozenBalance", comment: "Frozen Balance"))
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                } else if hasError {
                    // Error state - show dash
                    Text("-- TRX")
                        .font(Theme.fonts.priceBodyS)
                        .foregroundStyle(Theme.colors.textPrimary)
                    Text(NSLocalizedString("tronRowFrozenBalance", comment: "Frozen Balance"))
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                } else if let balance = frozenBalance, balance > 0 {
                    // Has positive frozen balance - show amount
                    Text("\(balance.formatted()) TRX")
                        .font(Theme.fonts.priceBodyS)
                        .foregroundStyle(Theme.colors.textPrimary)
                    Text(NSLocalizedString("tronRowFrozen", comment: "Frozen"))
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                } else {
                    // No frozen balance - show available
                    let available = TronViewLogic.getWalletTrxBalance(vault: vault)
                    Text("\(available.formatted()) TRX")
                        .font(Theme.fonts.priceBodyS)
                        .foregroundStyle(Theme.colors.textPrimary)
                    Text(NSLocalizedString("tronRowAvailable", comment: "Available"))
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                }
            } else {
                // No TRX - show Get Started
                Text(NSLocalizedString("tronRowGetStarted", comment: "Get Started"))
                    .font(Theme.fonts.priceBodyS)
                    .foregroundStyle(Theme.colors.primaryAccent4)
            }
        }
    }
    
    private func loadBalance() async {
        guard TronViewLogic.getTrxCoin(vault: vault) != nil else {
            await MainActor.run {
                isLoading = false
            }
            return
        }
        
        do {
            let (_, frozenBandwidth, frozenEnergy, _) = try await logic.fetchData(vault: vault)
            await MainActor.run {
                frozenBalance = frozenBandwidth + frozenEnergy
                isLoading = false
                hasError = false
            }
        } catch {
            print("DefiTronRow: Error loading balance: \(error.localizedDescription)")
            await MainActor.run {
                isLoading = false
                hasError = true
            }
        }
    }
}
