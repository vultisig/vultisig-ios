//
//  HomeDefiTotalsStore.swift
//  VultisigApp
//

import SwiftUI

/// The selected vault's DeFi totals, computed once per change for every home
/// surface that shows a balance.
///
/// `HomeScreen` owns it in a plain `@State` and never reads it; only the
/// balance leaves observe it, so a DeFi refresh never rebuilds the pages.
@MainActor
final class HomeDefiTotalsStore: ObservableObject {
    @Published private(set) var totals = DefiTotals()

    func update(_ newTotals: DefiTotals) {
        guard newTotals != totals else { return }
        totals = newTotals
    }
}

extension EnvironmentValues {
    /// The home pager's selected tab, for the leaves that depend on it.
    @Entry var homeSelectedTab: HomeTab = .wallet
    /// Pages whose data the header shows even while they are off screen, so
    /// they refresh as if visible.
    @Entry var homeAlwaysFreshPages: Set<HomeTab> = []
}

/// Keeps `store` current for `vault`. Position rows mutate in place without
/// firing the vault's `objectWillChange`, so this listens for the position
/// store's notification as well as the vault's own DeFi fields.
///
/// The walk runs once on appear so the first DeFi balance is never a stale
/// zero, then only while `isNeeded`: a change that lands while no visible
/// balance shows DeFi is caught up when one does.
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
            // Rate and currency refreshes republish the wallet total; DeFi
            // values move with the same rates.
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
    /// Keeps `store` current with `vault`'s DeFi positions and rates while a
    /// visible balance `isNeeded`.
    func trackingDefiTotals(of vault: Vault, in store: HomeDefiTotalsStore, isNeeded: Bool) -> some View {
        modifier(DefiTotalsTracking(vault: vault, store: store, isNeeded: isNeeded))
    }
}
