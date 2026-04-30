//
//  DefiChainLPsViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/10/2025.
//

import Foundation
import OSLog
import SwiftData

private let logger = Logger(subsystem: "com.vultisig.app", category: "defi-chain-lps-view-model")

@MainActor
final class DefiChainLPsViewModel: ObservableObject {
    @Published private(set) var vault: Vault
    @Published private(set) var lpPositions: [LPPosition] = []
    @Published private(set) var initialLoadingDone: Bool = false
    @Published private(set) var refreshError: String?

    var hasLPPositions: Bool {
        !vaultLPPositions.isEmpty
    }

    var vaultLPPositions: [CoinMeta] {
        vault.defiPositions.first { $0.chain == chain }?.lps ?? []
    }

    private let interactor: LPsInteractor?
    private let storage: DefiPositionsStorageService
    private let chain: Chain

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
        self.lpPositions = persistedPositions()
        self.initialLoadingDone = !lpPositions.isEmpty
    }

    func update(vault: Vault) {
        self.vault = vault
        self.lpPositions = persistedPositions()
    }

    func refresh() async {
        refreshError = nil
        guard hasLPPositions else {
            // No LP coins enabled — preserve any prior in-memory state and just mark loaded.
            initialLoadingDone = true
            return
        }

        guard let interactor = interactor else {
            initialLoadingDone = true
            return
        }

        do {
            let dtos = try await interactor.fetchLPPositions(vault: vault)
            try storage.upsert(lp: dtos, for: vault)
            lpPositions = persistedPositions()
        } catch {
            // Preserve last-known UI state and surface error for the screen banner.
            logger.error("Failed to refresh LP positions for chain \(self.chain.rawValue, privacy: .public): \(error.localizedDescription, privacy: .private)")
            refreshError = "defiRefreshFailed".localized
        }
        initialLoadingDone = true
    }
}

private extension DefiChainLPsViewModel {
    func persistedPositions() -> [LPPosition] {
        vault.lpPositions.filter { vaultLPPositions.contains($0.coin2) }
    }
}
