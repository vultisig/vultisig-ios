//
//  DefiMainViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 16/10/2025.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "defi-main-view-model")

enum DefiMainItem: Identifiable, Hashable {
    case chain(Chain)
    case circle

    var id: String {
        switch self {
        case .chain(let chain): return chain.rawValue
        case .circle: return "circle"
        }
    }
}

@MainActor
final class DefiMainViewModel: ObservableObject {
    @Published private var chains = [Chain]()
    @Published private var showsCircle: Bool = false
    @Published var searchText: String = ""

    private let logic = VaultDetailLogic()
    private let positionsService = DefiPositionsService()
    private let storage: DefiPositionsStorageService

    init(storage: DefiPositionsStorageService = DefiPositionsStorageService()) {
        self.storage = storage
    }

    func filteredItems(in vault: Vault) -> [DefiMainItem] {
        let prefix: [DefiMainItem] = showsCircle && matchesSearch(circleName) ? [.circle] : []
        let filtered = chains.filter { chain in
            let nameMatches = chain.name.localizedCaseInsensitiveContains(searchText)
            let tickerMatches = vault.nativeCoin(for: chain)?.ticker
                .localizedCaseInsensitiveContains(searchText) ?? false
            return searchText.isEmpty || nameMatches || tickerMatches
        }
        return prefix + filtered.map { .chain($0) }
    }

    func groupChains(vault: Vault) {
        let defiChains = vault.chainsWithCoins.filter { chain in
            vault.defiChains.contains(chain) && CoinAction.defiChains.contains(chain)
        }

        chains = logic.sortedChains(
            chains: defiChains,
            value: { vault.coins(for: $0).totalDefiBalanceInFiatDecimal }
        )

        showsCircle = vault.isCircleEnabled && vault.chains.contains(.ethereum)
    }

    /// Refresh DeFi positions for chains whose dedicated screens don't persist them.
    /// Currently this only covers Tron — `TronView` reads frozen TRX into its own
    /// `@Published` state and never persists into `vault.stakePositions`, so the DeFi
    /// Portfolio row would otherwise stay stale until the user opens it.
    func refreshExternalChainPositions(vault: Vault) async {
        guard vault.chains.contains(.tron) else { return }
        ensureDefiPositionsSeed(for: .tron, in: vault)
        await refreshStakePositions(for: .tron, in: vault)
    }

    private var circleName: String { "Circle" }

    private func matchesSearch(_ value: String) -> Bool {
        searchText.isEmpty || value.localizedCaseInsensitiveContains(searchText)
    }
}

private extension DefiMainViewModel {
    /// Tron has no per-chain selection screen (the way THORChain / MayaChain do via
    /// `DefiChainSelectPositionsScreen`), so `vault.defiPositions` would never get a
    /// `.tron` entry. Seed one with the canonical TRX coin so `getStakedBalances` has
    /// something to filter against.
    func ensureDefiPositionsSeed(for chain: Chain, in vault: Vault) {
        let stakeCoins = positionsService.stakeCoins(for: chain)
        guard !stakeCoins.isEmpty else { return }

        if let existing = vault.defiPositions.first(where: { $0.chain == chain }) {
            let stakingSet = Set(existing.staking)
            let toAdd = stakeCoins.filter { !stakingSet.contains($0) }
            guard !toAdd.isEmpty else { return }
            existing.staking.append(contentsOf: toAdd)
        } else {
            vault.defiPositions.append(
                DefiPositions(chain: chain, bonds: [], staking: stakeCoins, lps: [])
            )
        }

        do {
            try Storage.shared.save()
        } catch {
            logger.error("Failed to seed defiPositions for \(chain.rawValue, privacy: .public): \(error.localizedDescription, privacy: .private)")
        }
    }

    func refreshStakePositions(for chain: Chain, in vault: Vault) async {
        guard let interactor = DefiInteractorResolver.stakeInteractor(for: chain) else { return }
        let dtos = await interactor.fetchStakePositions(vault: vault)
        do {
            try storage.upsert(stake: dtos, for: vault)
        } catch {
            logger.error("Failed to persist stake positions for \(chain.rawValue, privacy: .public): \(error.localizedDescription, privacy: .private)")
        }
    }
}
