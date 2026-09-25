//
//  DefiChainBondViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/10/2025.
//

import Foundation
import OSLog

private let logger = Log.defi.viewModel

@MainActor
final class DefiChainBondViewModel: ObservableObject {
    @Published private(set) var vault: Vault
    @Published private(set) var activeBondedNodes: [BondPosition] = []
    @Published private(set) var availableNodes: [BondNode] = []
    @Published private(set) var canUnbond: Bool = false
    @Published private(set) var canAddBond: Bool = false
    @Published private(set) var refreshError: String?

    private var totalBondedDecimal: Decimal {
        activeBondedNodes.map(\.amount).reduce(.zero, +)
    }

    var totalBondedBalance: String {
        guard let nativeCoin = vault.nativeCoin(for: chain) else { return "" }
        return nativeCoin.formatWithTicker(value: totalBondedDecimal)
    }

    var totalBondedBalanceFiat: String {
        guard let nativeCoin = vault.nativeCoin(for: chain) else { return "" }
        return nativeCoin.fiat(decimal: nativeCoin.valueWithDecimals(value: totalBondedDecimal)).formatToFiat()
    }

    var hasBondPositions: Bool {
        vault.defiPositions.contains { $0.bonds.contains(where: { $0.chain == chain }) }
    }

    /// Whether to offer unbonding from a node the user has no card for.
    ///
    /// Active nodes are discovered by querying the bond address, so a node that
    /// stopped reporting the user as a provider leaves them with no route out at
    /// all. On MayaChain the unbond form re-fetches everything it needs from a
    /// typed address, so a blank entry point is a complete flow. THORChain's
    /// unbond validates the amount against the bond the card carries, so it stays
    /// card-driven.
    var canUnbondFromUnlistedNode: Bool {
        chain == .mayaChain && canUnbond
    }
    private let interactor: BondInteractor?
    private let chain: Chain

    init(vault: Vault, chain: Chain, interactor: BondInteractor? = nil) {
        self.vault = vault
        self.chain = chain
        self.interactor = interactor ?? DefiInteractorResolver.bondInteractor(for: chain)
    }

    /// Rebinds to the vault the screen now shows, and re-seeds the node lists
    /// from it.
    ///
    /// The re-seed is what the stake and LP view models get for free: their
    /// position arrays are computed off the live vault relationship, so a rebind
    /// re-derives them. These two are published caches, so leaving them would
    /// show the previous vault's bonds — and the `totalBondedBalance` derived
    /// from them — under the new vault until a refresh for it completes.
    /// `availableNodes` and the error are dropped rather than re-seeded because
    /// both describe a fetch made for the vault being left.
    ///
    /// The vault is adopted unconditionally, and only the cleanup is conditional:
    /// the same vault can arrive as a freshly fetched instance, and keeping the
    /// previous one would leave this reading relationships through a superseded
    /// object. Re-seeding on that path, though, would throw away a node list that
    /// is still current.
    func update(vault: Vault) {
        let isDifferentVault = vault.pubKeyECDSA != self.vault.pubKeyECDSA
        self.vault = vault
        guard isDifferentVault else { return }
        // Mirrors the cache-first rule in `refresh()`: a vault that has not
        // opted this chain in shows nothing, however much it has persisted.
        activeBondedNodes = hasBondPositions
            ? sortedActiveBonds(vault.bondPositions.filter { $0.node.coin.chain == chain })
            : []
        availableNodes = []
        refreshError = nil
    }

    func refresh() async {
        refreshError = nil
        guard let interactor = interactor else {
            self.canUnbond = false
            self.canAddBond = false
            return
        }

        if hasBondPositions {
            activeBondedNodes = sortedActiveBonds(
                vault.bondPositions.filter { $0.node.coin.chain == chain }
            )
        }

        // Read the published vault here, on the main actor; the `async let`
        // child task would otherwise read the property off it.
        let refreshingVault = vault
        async let canUnbondTask = interactor.canUnbond()
        async let canAddBondTask = interactor.canAddBond()
        async let fetchTask = interactor.fetchBondPositions(vault: refreshingVault)

        // Both capability answers are about `chain`, which is fixed for this view
        // model's lifetime — neither takes a vault — so they survive a vault
        // switch and are published as soon as they arrive, without waiting on the
        // position fetch below.
        self.canUnbond = await canUnbondTask
        self.canAddBond = await canAddBondTask

        let fetched: (active: [BondPosition], available: [BondNode])?
        do {
            fetched = try await fetchTask
        } catch {
            // Preserve last-known UI state on transient failures so cached positions stay visible
            logger.error("Failed to refresh bond positions for chain \(self.chain.rawValue, privacy: .public): \(error)")
            fetched = nil
        }

        // The screen is built once and outlives a vault switch, so `vault` may
        // have been rebound while the fetch was suspended. What follows describes
        // `refreshingVault` — the error included, since it stands for a fetch made
        // for that vault — so a superseded pass publishes none of it.
        guard vault.pubKeyECDSA == refreshingVault.pubKeyECDSA else { return }

        guard let fetched else {
            self.refreshError = "defiRefreshFailed".localized
            return
        }
        self.activeBondedNodes = sortedActiveBonds(fetched.active)
        self.availableNodes = fetched.available
    }

    private func sortedActiveBonds(_ positions: [BondPosition]) -> [BondPosition] {
        DefiPositionOrdering.descending(
            positions,
            value: \.amount,
            tieBreak: \.id
        )
    }
}
