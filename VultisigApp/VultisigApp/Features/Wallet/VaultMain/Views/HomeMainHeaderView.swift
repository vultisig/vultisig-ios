//
//  VaultMainHeaderView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 09/09/2025.
//

import SwiftUI

struct HomeMainHeaderView: View {
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    let vault: Vault
    @Binding var activeTab: HomeTab
    @Binding var showBalance: Bool
    var vaultSelectorAction: () -> Void
    var settingsAction: () -> Void
    var onRefresh: () -> Void
    
    @State private var showBalanceInternal = false
    
    var balanceText: String {
        activeTab == .defi ? homeViewModel.defiBalanceText(for: vault) : homeViewModel.balanceText(for: vault)
    }
    
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
                .foregroundStyle(Theme.colors.textTertiary)
            Text(balanceText)
                .font(Theme.fonts.priceBodyS)
                .foregroundStyle(Theme.colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.numericText())
                .animation(.interpolatingSpring, value: balanceText)
        }
        .scaledToFit()
    }
    
    var buttonsStack: some View {
        HStack(spacing: 8) {
            #if os(macOS)
            RefreshToolbarButton(onRefresh: onRefresh)
            #endif

            ToolbarButton(image: "settings", action: settingsAction)
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
        HomeMainHeaderView(
            vault: .example,
            activeTab: .constant(.wallet),
            showBalance: .constant(true)
        ) {
            print("Vault Selector Action")
        } settingsAction: {
            print("Settings action")
        } onRefresh: {
            print("On refresh action")
        }
    }
    .background(Theme.colors.bgPrimary)
    .environmentObject(HomeViewModel())
}
