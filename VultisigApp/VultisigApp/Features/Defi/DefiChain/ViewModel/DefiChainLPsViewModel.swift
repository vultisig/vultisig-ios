//
//  DefiChainLPsViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/10/2025.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "defi-chain-lps-view-model")

@MainActor
final class DefiChainLPsViewModel: ObservableObject {
    @Published private(set) var vault: Vault
    @Published private(set) var initialLoadingDone: Bool

    private let chain: Chain
    private let interactor: LPsInteractor?
    private let storage: DefiPositionsStorageService

    /// See `DefiChainStakeViewModel.stakePositions` for why this is computed and not cached.
    var lpPositions: [LPPosition] {
        vault.lpPositions.filter { vaultLPPositions.contains($0.coin2) }
    }

    var hasLPPositions: Bool { !vaultLPPositions.isEmpty }

    var vaultLPPositions: [CoinMeta] {
        vault.defiPositions.first { $0.chain == chain }?.lps ?? []
    }

    init(
        vault: Vault,
        chain: Chain,
        interactor: LPsInteractor? = nil,
        storage: DefiPositionsStorageService = DefiPositionsStorageService()
    ) {
        self.vault = vault
        self.chain = chain
        self.interactor = interactor ?? DefiInteractorResolver.lpsInteractor(for: chain)
        self.storage = storage
        self.initialLoadingDone = !vault.lpPositions.isEmpty
    }

    func update(vault: Vault) {
        self.vault = vault
    }

    func refresh() async {
        guard let interactor else {
            initialLoadingDone = true
            return
        }

        let dtos = await interactor.fetchLPPositions(vault: vault)
        do {
            try storage.upsert(lp: dtos, for: vault)
        } catch {
            logger.error("Failed to persist LP positions for chain \(self.chain.rawValue, privacy: .public): \(error.localizedDescription, privacy: .private)")
        }
        initialLoadingDone = true
    }
}
