//
//  HomeDefiTotalsStore.swift
//  VultisigApp
//

import SwiftUI

/// Observed only by the balance leaves, so a DeFi refresh never rebuilds the pages.
@MainActor
final class HomeDefiTotalsStore: ObservableObject {
    @Published private(set) var totals = DefiTotals()

    func update(_ newTotals: DefiTotals) {
        guard newTotals != totals else { return }
        totals = newTotals
    }
}

extension EnvironmentValues {
    @Entry var homeSelectedTab: HomeTab = .wallet
    /// Pages whose data the header shows even while they are off screen, so
    /// they refresh as if visible.
    @Entry var homeAlwaysFreshPages: Set<HomeTab> = []
}

/// Position rows mutate in place without firing the vault's `objectWillChange`, hence the notification.
private struct DefiTotalsTracking: ViewModifier {
    @ObservedObject var vault: Vault
    let store: HomeDefiTotalsStore
    let isNeeded: Bool

    @EnvironmentObject var vaultDetailViewModel: VaultDetailViewModel
    @State private var isStale = false

    private let defiBalanceService = DefiBalanceService()

    func body(content: Content) -> some View {
        content
            .onAppear(perform: recompute)
            .onChange(of: isNeeded) { _, isNeeded in
                if isNeeded && isStale { recompute() }
            }
            .onChange(of: vault) { _, _ in update() }
            .onChange(of: vault.defiChains) { _, _ in update() }
            .onChange(of: vault.defiPositions) { _, _ in update() }
            // Rate refreshes republish the wallet total; DeFi values move with them.
            .onChange(of: vaultDetailViewModel.totalFiatBalance) { _, _ in update() }
            .onReceive(NotificationCenter.default.publisher(for: .defiPositionsDidChange)) { _ in
                update()
            }
    }

    private func update() {
        guard isNeeded else {
            isStale = true
            return
        }
        recompute()
    }

    private func recompute() {
        isStale = false
        store.update(defiBalanceService.totals(for: vault.defiChains, vault: vault))
    }
}

extension View {
    func trackingDefiTotals(of vault: Vault, in store: HomeDefiTotalsStore, isNeeded: Bool) -> some View {
        modifier(DefiTotalsTracking(vault: vault, store: store, isNeeded: isNeeded))
    }
}
