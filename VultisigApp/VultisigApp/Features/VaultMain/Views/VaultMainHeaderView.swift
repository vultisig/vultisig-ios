//
//  VaultMainHeaderView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 09/09/2025.
//

import SwiftUI

struct VaultMainHeaderView: View {
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    let vault: Vault
    @Binding var showBalance: Bool
    var vaultSelectorAction: () -> Void
    var settingsAction: () -> Void
    
    @State private var showBalanceInternal = false
    
    var body: some View {
        HStack(spacing: 32) {
            VaultSelectorView(
                vaultName: vault.name,
                isFastVault: vault.isFastVault,
                action: vaultSelectorAction
            )
            
            HStack {
                Spacer()
                trailingView
                    .transition(.opacity)
            }
        }
        .padding(.top, isMacOS ? 16 : 0)
        .padding(.bottom, 16)
        .padding(.horizontal, 16)
        .background(backgroundView)
        .onChange(of: showBalance) { _, newValue in
            withAnimation(.interpolatingSpring) {
                showBalanceInternal = newValue
            }
        }
    }
    
    @ViewBuilder
    var trailingView: some View {
        if showBalanceInternal {
            balanceView
        } else {
            buttonsStack
        }
    }
    
    var balanceView: some View {
        VStack(spacing: 4) {
            Text("portfolioBalance".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textExtraLight)
            Text(homeViewModel.vaultBalanceText)
                .font(Theme.fonts.priceBodyS)
                .foregroundStyle(Theme.colors.textPrimary)
        }
    }
    
    var buttonsStack: some View {
        HStack(spacing: 8) {
            CircularIconButton(icon: "settings", action: settingsAction)
        }
    }
    
    var backgroundView: some View {
        VStack(spacing: 0) {
            Theme.colors.bgPrimary
            Separator(color: Theme.colors.borderLight, opacity: 1)
        }
        .ignoresSafeArea(.all)
        .transition(.opacity)
        .showIf(showBalanceInternal)
    }
}

#Preview {
    VStack {
        VaultMainHeaderView(vault: .example, showBalance: .constant(true)) {
            print("Vault Selector Action")
        } settingsAction: {
            print("Settings action")
        }
    }
    .background(Theme.colors.bgPrimary)
    .environmentObject(HomeViewModel())
}
