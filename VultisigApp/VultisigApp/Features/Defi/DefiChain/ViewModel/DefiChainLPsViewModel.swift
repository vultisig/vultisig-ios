//
//  DefiChainLPsViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/10/2025.
//

import Foundation
import SwiftData

@MainActor
final class DefiChainLPsViewModel: ObservableObject {
    @Published private(set) var vault: Vault
    @Published private(set) var lpPositions: [LPPosition] = []
    @Published private(set) var initialLoadingDone: Bool = false

    var hasLPPositions: Bool {
        !vaultLPPositions.isEmpty
    }

    var vaultLPPositions: [CoinMeta] {
        vault.defiPositions.first { $0.chain == chain }?.lps ?? []
    }

    private let interactor: LPsInteractor?
    private let chain: Chain

    init(vault: Vault, chain: Chain) {
        self.vault = vault
        self.chain = chain
        self.interactor = DefiInteractorResolver.lpsInteractor(for: chain)
        self.lpPositions = cachedPositions()
        self.initialLoadingDone = !lpPositions.isEmpty
    }

    func update(vault: Vault) {
        self.vault = vault
        self.lpPositions = cachedPositions()
    }

    func refresh() async {
        guard hasLPPositions else {
            // No LP coins enabled — preserve any prior in-memory state and just mark loaded.
            initialLoadingDone = true
            return
        }

        guard let interactor = interactor else {
            initialLoadingDone = true
            return
        }

        let positions = await interactor.fetchLPPositions(vault: vault)
        if !positions.isEmpty {
            lpPositions = positions
        }
        initialLoadingDone = true
    }
}

private extension DefiChainLPsViewModel {
    func cachedPositions() -> [LPPosition] {
        vault.lpPositions.filter { vaultLPPositions.contains($0.coin2) }
    }
}
