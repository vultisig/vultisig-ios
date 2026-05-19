//
//  DefiChainBondViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/10/2025.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "defi-chain-bond-view-model")

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
    private let interactor: BondInteractor?
    private let chain: Chain

    init(vault: Vault, chain: Chain) {
        self.vault = vault
        self.chain = chain
        self.interactor = DefiInteractorResolver.bondInteractor(for: chain)
    }

    func update(vault: Vault) {
        self.vault = vault
    }

    func refresh() async {
        refreshError = nil
        guard let interactor = interactor else {
            self.canUnbond = false
            self.canAddBond = false
            return
        }

        if hasBondPositions {
            activeBondedNodes = vault.bondPositions.filter { $0.node.coin.chain == chain }
        }

        async let canUnbondTask = interactor.canUnbond()
        async let canAddBondTask = interactor.canAddBond(vault: vault)
        async let fetchTask = interactor.fetchBondPositions(vault: vault)

        self.canUnbond = await canUnbondTask
        self.canAddBond = await canAddBondTask

        do {
            let (active, available) = try await fetchTask
            self.activeBondedNodes = active
            self.availableNodes = available
        } catch {
            // Preserve last-known UI state on transient failures so cached positions stay visible
            logger.error("Failed to refresh bond positions for chain \(self.chain.rawValue, privacy: .public): \(error)")
            self.refreshError = "defiRefreshFailed".localized
        }
    }
}
