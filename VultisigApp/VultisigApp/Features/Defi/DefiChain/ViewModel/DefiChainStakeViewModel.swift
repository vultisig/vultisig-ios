//
//  DefiChainStakeViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/10/2025.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "defi-chain-stake-view-model")

@MainActor
final class DefiChainStakeViewModel: ObservableObject {
    @Published private(set) var vault: Vault
    @Published private(set) var initialLoadingDone: Bool

    private let chain: Chain
    private let interactor: StakeInteractor?
    private let storage: DefiPositionsStorageService

    /// Computed against the live `vault.stakePositions` relationship rather than a cached
    /// snapshot. Caching here would let the view dereference a `StakePosition` after storage
    /// deletes it (e.g. when the user disables a position) and crash on attribute fault. The
    /// host screen's `@ObservedObject vault` re-renders whenever the relationship changes, so
    /// this property re-evaluates with a fresh array.
    var stakePositions: [StakePosition] {
        vault.stakePositions
            .filter { vaultStakePositions.contains($0.coin) }
            .sorted { $0.amount > $1.amount }
    }

    var hasStakePositions: Bool { !stakePositions.isEmpty }

    var vaultStakePositions: [CoinMeta] {
        vault.defiPositions.first { $0.chain == chain }?.staking ?? []
    }

    init(
        vault: Vault,
        chain: Chain,
        interactor: StakeInteractor? = nil,
        storage: DefiPositionsStorageService = DefiPositionsStorageService()
    ) {
        self.vault = vault
        self.chain = chain
        self.interactor = interactor ?? DefiInteractorResolver.stakeInteractor(for: chain)
        self.storage = storage
        let enabledStakes = vault.defiPositions.first { $0.chain == chain }?.staking ?? []
        self.initialLoadingDone = vault.stakePositions.contains { enabledStakes.contains($0.coin) }
    }

    func update(vault: Vault) {
        self.vault = vault
    }

    func refresh() async {
        guard let interactor else {
            initialLoadingDone = true
            return
        }

        let dtos = await interactor.fetchStakePositions(vault: vault)
        do {
            try storage.upsert(stake: dtos, for: vault)
        } catch {
            logger.error("Failed to persist stake positions for chain \(self.chain.rawValue, privacy: .public): \(error.localizedDescription, privacy: .private)")
        }
        initialLoadingDone = true
    }
}
