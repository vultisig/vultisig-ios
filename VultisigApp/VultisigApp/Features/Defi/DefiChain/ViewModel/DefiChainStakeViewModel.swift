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
        self.vault = vault
    }

    func refresh() async {
        guard let interactor else {
            actionAvailabilities = Self.resolvedActionAvailabilities(
                for: vaultStakePositions,
                availability: chain == .mayaChain ? .unavailable : .available
            )
            initialLoadingDone = true
            return
        }

        let enabledCoins = vaultStakePositions
        async let positions = interactor.fetchStakePositions(vault: vault)
        async let availabilities = interactor.fetchActionAvailabilities(for: enabledCoins)
        let (dtos, resolvedAvailabilities) = await (positions, availabilities)
        actionAvailabilities = resolvedAvailabilities
        do {
            try storage.upsert(stake: dtos, for: vault)
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
