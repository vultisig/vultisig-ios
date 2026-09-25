//
//  DefiChainStakeViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/10/2025.
//

import Foundation
import OSLog

private let logger = Log.defi.viewModel

@MainActor
final class DefiChainStakeViewModel: ObservableObject {
    @Published private(set) var vault: Vault
    @Published private(set) var initialLoadingDone: Bool
    @Published private(set) var actionAvailabilities: StakeActionAvailabilities

    private let chain: Chain
    private let interactor: StakeInteractor?
    private let storage: DefiPositionsStorageService

    private var isRefreshing = false
    private var refreshQueued = false

    /// Computed against the live `vault.stakePositions` relationship rather than a cached
    /// snapshot. Caching here would let the view dereference a `StakePosition` after storage
    /// deletes it (e.g. when the user disables a position) and crash on attribute fault. The
    /// host screen's `@ObservedObject vault` re-renders whenever the relationship changes, so
    /// this property re-evaluates with a fresh array.
    var stakePositions: [StakePosition] {
        vault.stakePositions
            .filter { isEnabled($0) }
            .sorted { $0.amount > $1.amount }
    }

    var hasStakePositions: Bool { !stakePositions.isEmpty }

    var vaultStakePositions: [CoinMeta] {
        vault.defiPositions.first { $0.chain == chain }?.staking ?? []
    }

    func actionAvailability(for position: StakePosition) -> StakeActionAvailability {
        actionAvailabilities[position.coin] ?? .available
    }

    /// Whether a persisted position should be shown for this chain. TON nominator
    /// staking is a single always-relevant position (like Tron) and is NOT gated
    /// behind the per-coin opt-in (`defiPositions[.ton].staking`): any TON stake
    /// shows immediately. THOR/Maya/Cosmos keep their opt-in.
    private func isEnabled(_ position: StakePosition) -> Bool {
        if chain == .ton {
            return position.coin.chain == .ton
        }
        return vaultStakePositions.contains(position.coin)
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
        self.actionAvailabilities = Self.initialActionAvailabilities(
            for: vault.defiPositions.first { $0.chain == chain }?.staking ?? [],
            chain: chain
        )
        // Mirror the per-chain visibility rule: TON shows any persisted stake
        // ungated; other chains require the per-coin opt-in.
        if chain == .ton {
            self.initialLoadingDone = vault.stakePositions.contains { $0.coin.chain == .ton }
        } else {
            let enabledStakes = vault.defiPositions.first { $0.chain == chain }?.staking ?? []
            self.initialLoadingDone = vault.stakePositions.contains { enabledStakes.contains($0.coin) }
        }
    }

    func update(vault: Vault) {
        let previousVaultKey = self.vault.pubKeyECDSA
        self.vault = vault
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
            actionAvailabilities = Self.resolvedActionAvailabilities(
                for: vaultStakePositions,
                availability: chain == .mayaChain ? .unavailable : .available
            )
            initialLoadingDone = true
            return
        }

        let enabledCoins = vaultStakePositions
        // Read the published vault here, on the main actor; the `async let`
        // child task would otherwise read the property off it.
        let refreshingVault = vault
        async let positions = interactor.fetchStakePositions(vault: refreshingVault)
        async let availabilities = interactor.fetchActionAvailabilities(for: enabledCoins)
        let (dtos, resolvedAvailabilities) = await (positions, availabilities)

        // The screen is built once and outlives a vault switch, so `vault` may have
        // been rebound while the fetch was suspended. Everything below describes
        // `refreshingVault`; applying it now would paint, and persist, one vault's
        // positions under another's identity.
        guard vault.pubKeyECDSA == refreshingVault.pubKeyECDSA else { return }

        actionAvailabilities = resolvedAvailabilities
        do {
            try storage.upsert(stake: dtos, for: refreshingVault)
        } catch {
            logger.error("Failed to persist stake positions for chain \(self.chain.rawValue, privacy: .public): \(error.localizedDescription, privacy: .private)")
        }
        initialLoadingDone = true
    }
}

private extension DefiChainStakeViewModel {
    static func initialActionAvailabilities(for coins: [CoinMeta], chain: Chain) -> StakeActionAvailabilities {
        resolvedActionAvailabilities(
            for: coins,
            availability: chain == .mayaChain ? .checking : .available
        )
    }

    static func resolvedActionAvailabilities(
        for coins: [CoinMeta],
        availability: StakeActionAvailability
    ) -> StakeActionAvailabilities {
        coins.reduce(into: [:]) { result, coin in
            result[coin] = availability
        }
    }
}
