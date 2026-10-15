//
//  HomePortfolioHeaderView.swift
//  VultisigApp
//

import SwiftUI

/// The home's large balance and action buttons, drawn once by `HomeFloatingHeader`.
struct HomePortfolioHeaderView: View, Equatable {
    @ObservedObject var vault: Vault
    let onAction: (CoinAction) -> Void

    @EnvironmentObject var homeViewModel: HomeViewModel
    @EnvironmentObject var vaultDetailViewModel: VaultDetailViewModel
    @EnvironmentObject var defiTotalsStore: HomeDefiTotalsStore
    @Environment(\.homeSelectedTab) private var selectedTab

    private let horizontalPadding: CGFloat = 16

    /// Ignores `onAction`: Home recreates it every update, but it routes the same way per vault.
    static func == (lhs: HomePortfolioHeaderView, rhs: HomePortfolioHeaderView) -> Bool {
        lhs.vault === rhs.vault
    }

    var body: some View {
        VStack(spacing: 0) {
            VaultMainBalanceView(vault: vault, balanceToShow: balanceText, style: .wallet)
                .modifier(HomeHeaderBalanceFade())
                .padding(.bottom, 32)

            CoinActionsView(actions: vaultDetailViewModel.availableActions, onAction: onAction)
        }
        .padding(.horizontal, horizontalPadding)
    }

    /// The selected tab's total, so the number rolls once a swipe settles.
    private var balanceText: String {
        guard !homeViewModel.hideVaultBalance else { return String.hideBalanceText }
        return homeViewModel.balanceDisplay
            .total(
                for: selectedTab,
                wallet: vaultDetailViewModel.walletTotal(for: vault),
                defi: defiTotalsStore.totals
            )
            .formatToFiat(includeCurrencySymbol: true)
    }
}

/// Its own modifier so the per-frame opacity re-applies to the balance alone.
private struct HomeHeaderBalanceFade: ViewModifier {
    @Environment(\.homeHeaderBalanceOpacity) private var opacity

    func body(content: Content) -> some View {
        content.headerCollapseOpacity(opacity)
    }
}
