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
    private let chain: Chain
    @Published private(set) var stakePositions: [StakePosition] = []
    @Published private(set) var initialLoadingDone: Bool = false
    @Published private(set) var refreshError: String?

    var hasStakePositions: Bool {
        !stakePositions.isEmpty
    }

    var vaultStakePositions: [CoinMeta] {
        vault.defiPositions.first { $0.chain == chain }?.staking ?? []
    }
    private let interactor: StakeInteractor?
    private let storage: DefiPositionsStorageService

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
        self.stakePositions = persistedPositions()
        self.initialLoadingDone = !stakePositions.isEmpty
    }

    func update(vault: Vault) {
        self.vault = vault
        self.stakePositions = persistedPositions()
    }

    func refresh() async {
        refreshError = nil
        guard let interactor = interactor else {
            initialLoadingDone = true
            return
        }

        let dtos = await interactor.fetchStakePositions(vault: vault)
        do {
            try storage.upsert(stake: dtos, for: vault)
            stakePositions = persistedPositions()
        } catch {
            logger.error("Failed to persist stake positions for chain \(self.chain.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            refreshError = "defiRefreshFailed".localized
        }
        initialLoadingDone = true
    }
}

private extension DefiChainStakeViewModel {
    /// Reads current persisted positions filtered by the user's enabled stake coins.
    /// Safe to call after `upsert` because interactors no longer construct `@Model`
    /// instances (which would have polluted `vault.stakePositions` via the inverse
    /// relationship before save). DTOs flow through the storage materialization
    /// boundary and are the only path to mutating `vault.stakePositions`.
    func persistedPositions() -> [StakePosition] {
        vault.stakePositions
            .filter { vaultStakePositions.contains($0.coin) }
            .sorted { $0.amount > $1.amount }
    }
}
