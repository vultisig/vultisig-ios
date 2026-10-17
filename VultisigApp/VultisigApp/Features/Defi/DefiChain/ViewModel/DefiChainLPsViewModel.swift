//
//  DefiChainLPsViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/10/2025.
//

import Foundation
import OSLog

private let logger = Log.defi.viewModel

@MainActor
final class DefiChainLPsViewModel: ObservableObject {
    @Published private(set) var vault: Vault
    @Published private(set) var initialLoadingDone: Bool
    /// Half-finished paired adds MayaChain is holding, separate from the
    /// positions: a deposit stuck in a pool the user never enabled is exactly
    /// the one that would otherwise be refunded unseen.
    @Published private(set) var pendingDeposits: [MayaPendingLPDeposit] = []
    /// False once a rescan has failed. The cards stay, their refund timer is
    /// still running, but Complete is withdrawn: nothing confirms MayaChain has
    /// not refunded them since.
    @Published private(set) var canCompletePendingDeposits = true

    private let chain: Chain
    private let interactor: LPsInteractor?
    private let storage: DefiPositionsStorageService

    private var isRefreshing = false
    private var refreshQueued = false

    /// See `DefiChainStakeViewModel.stakePositions` for why this is computed and not cached.
    var lpPositions: [LPPosition] {
        vault.lpPositions.filter { vaultLPPositions.contains($0.coin2) }
    }

    var hasLPPositions: Bool { !lpPositions.isEmpty }

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
        let enabledLPs = vault.defiPositions.first { $0.chain == chain }?.lps ?? []
        self.initialLoadingDone = vault.lpPositions.contains { enabledLPs.contains($0.coin2) }
    }

    func update(vault: Vault) {
        let previousVaultKey = self.vault.pubKeyECDSA
        self.vault = vault
        if previousVaultKey != vault.pubKeyECDSA {
            // Another vault's pending deposits are not this one's to complete.
            pendingDeposits = []
            canCompletePendingDeposits = true
        }
        if isRefreshing, previousVaultKey != vault.pubKeyECDSA {
            refreshQueued = true
        }
    }

    func refresh() async {
        guard !isRefreshing else {
            refreshQueued = true
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        repeat {
            refreshQueued = false
            await performRefresh()
        } while refreshQueued
    }

    private func performRefresh() async {
        guard let interactor else {
            initialLoadingDone = true
            return
        }

        // Read the published vault here, on the main actor, before suspending.
        let refreshingVault = vault
        let dtos = await interactor.fetchLPPositions(vault: refreshingVault)

        // See `DefiChainStakeViewModel.refresh()` for why a superseded pass has to
        // drop its results rather than apply them to whatever vault is bound now.
        guard vault.pubKeyECDSA == refreshingVault.pubKeyECDSA else { return }

        do {
            try storage.upsert(lp: dtos, for: refreshingVault)
        } catch {
            logger.error("Failed to persist LP positions for chain \(self.chain.rawValue, privacy: .public): \(error.localizedDescription, privacy: .private)")
        }
        initialLoadingDone = true
        await refreshPendingDeposits(for: refreshingVault)
    }

    private func refreshPendingDeposits(for refreshingVault: Vault) async {
        guard let provider = interactor as? PendingLPDepositsProviding else { return }
        do {
            let scan = try await provider.fetchPendingLPDeposits(vault: refreshingVault)
            guard vault.pubKeyECDSA == refreshingVault.pubKeyECDSA else { return }
            if scan.isComplete {
                pendingDeposits = scan.deposits
            } else {
                // A scan that missed a pool cannot say nothing is pending there,
                // so cards an earlier scan found stay unless this one re-read
                // their pool.
                let rescanned = Set(scan.deposits.map(\.pool))
                pendingDeposits = scan.deposits + pendingDeposits.filter { !rescanned.contains($0.pool) }
            }
            canCompletePendingDeposits = scan.isComplete
        } catch {
            logger.warning("Failed to load pending Maya LP deposits: \(error.localizedDescription, privacy: .private)")
            guard vault.pubKeyECDSA == refreshingVault.pubKeyECDSA else { return }
            canCompletePendingDeposits = false
        }
    }

    func canComplete(_ deposit: MayaPendingLPDeposit) -> Bool {
        canCompletePendingDeposits && MayaPendingLPPresentation.canComplete(deposit, in: vault)
    }
}
