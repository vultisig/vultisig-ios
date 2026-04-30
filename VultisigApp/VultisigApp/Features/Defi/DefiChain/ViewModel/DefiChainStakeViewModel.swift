//
//  DefiChainStakeViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/10/2025.
//

import Foundation

@MainActor
final class DefiChainStakeViewModel: ObservableObject {
    @Published private(set) var vault: Vault
    private let chain: Chain
    @Published private(set) var stakePositions: [StakePosition] = []
    @Published private(set) var initialLoadingDone: Bool = false

    var hasStakePositions: Bool {
        !stakePositions.isEmpty
    }

    var vaultStakePositions: [CoinMeta] {
        vault.defiPositions.first { $0.chain == chain }?.staking ?? []
    }
    private let interactor: StakeInteractor?

    init(vault: Vault, chain: Chain) {
        self.vault = vault
        self.chain = chain
        self.interactor = DefiInteractorResolver.stakeInteractor(for: chain)
        self.stakePositions = cachedPositions()
        self.initialLoadingDone = !stakePositions.isEmpty
    }

    func update(vault: Vault) {
        self.vault = vault
        self.stakePositions = cachedPositions()
    }

    func refresh() async {
        await loadStakePositions()
    }
}

private extension DefiChainStakeViewModel {
    func cachedPositions() -> [StakePosition] {
        vault.stakePositions
            .filter { vaultStakePositions.contains($0.coin) }
            .sorted { $0.amount > $1.amount }
    }

    func loadStakePositions() async {
        guard let interactor = interactor else {
            initialLoadingDone = true
            return
        }
        let positions = await interactor.fetchStakePositions(vault: vault)
        if !positions.isEmpty {
            stakePositions = positions
        }
        initialLoadingDone = true
    }
}
