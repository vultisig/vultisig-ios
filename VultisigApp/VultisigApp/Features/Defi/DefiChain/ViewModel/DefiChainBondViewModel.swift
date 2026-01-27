//
//  DefiChainBondViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/10/2025.
//

import Foundation

final class DefiChainBondViewModel: ObservableObject {
    @Published private(set) var vault: Vault
    @Published private(set) var activeBondedNodes: [BondPosition] = []
    @Published private(set) var availableNodes: [BondNode] = []
    @Published private(set) var canUnbond: Bool = false

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
        vault.defiPositions.contains { $0.chain == chain && !$0.bonds.isEmpty }
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

    @MainActor
    func refresh() async {
        guard hasBondPositions, let interactor = interactor else { return }
        activeBondedNodes = vault.bondPositions.filter { $0.node.coin.chain == chain }

        self.canUnbond = await interactor.canUnbond()
        let (active, available) = await interactor.fetchBondPositions(vault: vault)

        if !active.isEmpty {
            self.activeBondedNodes = active
        }

        if !available.isEmpty {
            self.availableNodes = available
        }
    }
}
