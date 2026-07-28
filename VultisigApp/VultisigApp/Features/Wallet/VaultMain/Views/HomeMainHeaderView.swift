//
//  VaultMainHeaderView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 09/09/2025.
//

import SwiftUI

struct HomeMainHeaderView: View {
    @EnvironmentObject var homeViewModel: HomeViewModel
    @EnvironmentObject var vaultDetailViewModel: VaultDetailViewModel

    let vault: Vault
    @Binding var activeTab: HomeTab
    @Binding var showBalance: Bool
    var vaultSelectorAction: () -> Void
    var historyAction: () -> Void
    var settingsAction: () -> Void
    var onRefresh: () -> Void

    @State private var showBalanceInternal = false

    /// Wallet total: the same guard-and-fallback shape as
    /// `VaultMainScreen.totalBalanceToShow`. `VaultDetailViewModel` publishes it
    /// preformatted, so the header no longer walks every coin through
    /// `RateProvider` on each body evaluation. The fallback covers the frames
    /// where the projection is not usable — before the first `refresh()` lands,
    /// and right after a vault switch while the published total still belongs to
    /// the previous vault.
    ///
    /// DeFi total: kept as an on-the-fly compute. Its only meaningful published
    /// source would be `DefiMainViewModel`, which `DefiMainScreen` owns as a
    /// `@StateObject` and is therefore unreachable from here, and
    /// `VaultDetailViewModel` has no trigger tied to a DeFi balance refresh — a
    /// value published there would go stale on exactly the tab that shows it.
    /// The walk is also far cheaper: it is filtered to the vault's DeFi chains
    /// and only runs while the DeFi tab is active.
    var balanceText: String {
        guard !homeViewModel.hideVaultBalance else { return String.hideBalanceText }
        guard activeTab != .defi else { return homeViewModel.defiBalanceText(for: vault) }
        guard let total = vaultDetailViewModel.totalFiatBalance,
              total.vaultPubKeyECDSA == vault.pubKeyECDSA else {
            return homeViewModel.balanceText(for: vault)
        }
        return total.text
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
                .accessibilityIdentifier(AccessibilityID.Home.balanceLabel)
        }
        .scaledToFit()
    }

    var buttonsStack: some View {
        HStack(spacing: 8) {
            #if os(macOS)
            RefreshToolbarButton(onRefresh: onRefresh)
            #endif

            ToolbarButton(image: .clockRotateClockwise, action: historyAction) { _ in
                Icon(.clockRotateClockwise, color: Theme.colors.textPrimary, size: 20)
            }
            .accessibilityIdentifier(AccessibilityID.Home.historyButton)
            ToolbarButton(image: .gear, action: settingsAction)
                .accessibilityIdentifier(AccessibilityID.Home.settingsButton)
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
        } historyAction: {
            print("History action")
        } settingsAction: {
            print("Settings action")
        } onRefresh: {
            print("On refresh action")
        }
    }
    .background(Theme.colors.bgPrimary)
    .environmentObject(HomeViewModel())
    .environmentObject(VaultDetailViewModel())
}
