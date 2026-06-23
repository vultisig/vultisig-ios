//
//  DefiMainViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 16/10/2025.
//

import Foundation

enum DefiMainItem: Identifiable, Hashable {
    case chain(Chain)
    case yield(DefiYieldProviderID)

    var id: String {
        switch self {
        case .chain(let chain): return chain.rawValue
        case .yield(let provider): return provider.rawValue
        }
    }
}

@MainActor
final class DefiMainViewModel: ObservableObject {
    @Published private var chains = [Chain]()
    @Published private var visibleProviders: [DefiYieldProviderID] = []
    @Published var searchText: String = ""

    private let logic = VaultDetailLogic()

    init() {}

    func filteredItems(in vault: Vault) -> [DefiMainItem] {
        let providerItems = visibleProviders
            .filter { matchesSearch(providerName($0)) }
            .map { DefiMainItem.yield($0) }
        let filtered = chains.filter { chain in
            let nameMatches = chain.name.localizedCaseInsensitiveContains(searchText)
            let tickerMatches = vault.nativeCoin(for: chain)?.ticker
                .localizedCaseInsensitiveContains(searchText) ?? false
            return searchText.isEmpty || nameMatches || tickerMatches
        }
        return providerItems + filtered.map { .chain($0) }
    }

    /// Refreshes persisted balances (including `Coin.stakedBalance`, which backs
    /// the TRON/Cosmos staking positions) and regroups. The DeFi main screen has
    /// no other trigger for a balance refresh — entering it directly without
    /// visiting the Wallet tab would otherwise show stale, never-fetched staked
    /// balances. Mirrors `DefiChainMainViewModel.refresh()`.
    func refreshBalances(vault: Vault) async {
        await BalanceService.shared.updateBalances(vault: vault)
        guard !Task.isCancelled else { return }
        groupChains(vault: vault)
    }

    func groupChains(vault: Vault) {
        // Backfill the provider array from the legacy flags the first time the
        // DeFi tab loads, then persist so the migration sticks.
        if vault.migrateLegacyDefiProvidersIfNeeded() {
            try? Storage.shared.save()
        }

        let defiChains = vault.chainsWithCoins.filter { chain in
            vault.defiChains.contains(chain) && CoinAction.defiChains.contains(chain)
        }

        chains = logic.sortedChains(
            chains: defiChains,
            value: { vault.coins(for: $0).totalDefiBalanceInFiatDecimal }
        )

        // A provider shows when it is enabled, the vault has Ethereum, and its
        // account (Circle MSCA) is provisioned. Account-less providers are
        // always provisioned, so the gate is uniform across providers.
        visibleProviders = DefiYieldProviderID.allCases.filter { isProviderVisible($0, in: vault) }
    }

    private func isProviderVisible(_ id: DefiYieldProviderID, in vault: Vault) -> Bool {
        guard vault.isDefiProviderEnabled(id), vault.chains.contains(.ethereum) else { return false }
        return DefiYieldProviderFactory.make(id).isAccountProvisioned(vault: vault)
    }

    private func providerName(_ id: DefiYieldProviderID) -> String {
        DefiYieldProviderFactory.make(id).presentation.providerNameKey.localized
    }

    private func matchesSearch(_ value: String) -> Bool {
        searchText.isEmpty || value.localizedCaseInsensitiveContains(searchText)
    }
}
