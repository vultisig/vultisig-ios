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
    /// Held as a plain `let`: this view must not re-evaluate when the collapse
    /// progress moves, because `balanceText` below is not free. The two things
    /// that do move with the scroll — the trailing slot and the bar's opaque
    /// background — observe it themselves.
    let collapse: HomeHeaderCollapse
    var vaultSelectorAction: () -> Void
    var historyAction: () -> Void
    var settingsAction: () -> Void
    var onRefresh: () -> Void

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
    /// and only runs while the DeFi tab is active. It is still a walk, though,
    /// which is why it is computed here and handed down as a plain `String`
    /// rather than being re-derived on every frame of a collapse.
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
                HomeMainHeaderTrailingView(
                    collapse: collapse,
                    tab: activeTab,
                    balanceText: balanceText,
                    historyAction: historyAction,
                    settingsAction: settingsAction,
                    onRefresh: onRefresh
                )
            }
        }
        .padding(.top, isMacOS ? 16 : 0)
        .padding(.bottom, 16)
        .padding(.horizontal, 16)
        .background(backgroundView)
        // Nothing here animates on a timeline: every opacity is a function of
        // the scroll offset. Switching tabs steps straight to the other tab's
        // stored progress rather than easing into it — easing would fade this
        // bar's balance out while the tab being switched to already has its
        // large balance on screen, which is the very overlap this is fixing.
    }

    var backgroundView: some View {
        VStack(spacing: 0) {
            Theme.colors.bgPrimary
            Separator(color: Theme.colors.borderLight, opacity: 1)
        }
        .ignoresSafeArea(.all)
        .headerCollapseReveal(collapse, tab: activeTab)
    }
}

/// The bar's trailing slot: toolbar buttons while the home is expanded, the
/// portfolio balance once it has collapsed.
///
/// Split out of `HomeMainHeaderView` so that it, and not the whole bar, is what
/// SwiftUI re-evaluates as the collapse progress moves — the bar's `balanceText`
/// walks the vault's DeFi coins on the DeFi tab, and that must not be redone on
/// every frame of a transition.
private struct HomeMainHeaderTrailingView: View {
    @ObservedObject var collapse: HomeHeaderCollapse
    let tab: HomeTab
    let balanceText: String
    let historyAction: () -> Void
    let settingsAction: () -> Void
    let onRefresh: () -> Void

    private var progress: HeaderCollapseProgress {
        collapse.progress(for: tab)
    }

    /// The buttons and the balance never overlap: the buttons have faded out by
    /// the time the swap happens, and the balance starts fading in from there,
    /// so the swap lands on the one point where both are invisible. Each side
    /// is ramped through `headerCollapseOpacity`, which is also what stops the
    /// buttons taking taps once they are no longer legible.
    var body: some View {
        if progress.isCollapsed {
            balanceView
                .headerCollapseOpacity(progress.collapsedOpacity)
        } else {
            buttonsStack
                .headerCollapseOpacity(progress.expandedOpacity)
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
}

#Preview {
    VStack {
        HomeMainHeaderView(
            vault: .example,
            activeTab: .constant(.wallet),
            collapse: HomeHeaderCollapse()
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
