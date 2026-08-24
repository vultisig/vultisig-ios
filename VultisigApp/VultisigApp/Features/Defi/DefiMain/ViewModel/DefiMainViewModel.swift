//
//  DefiMainViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 16/10/2025.
//

import Foundation
import OSLog

private let logger = Log.defi.viewModel

enum DefiMainItem: Identifiable, Hashable {
    case chain(Chain)
    case yield(DefiYieldProviderID)

    var id: String {
        switch self {
        case .chain(let chain): return chain.rawValue
        case .yield(let provider): return provider.rawValue
        }
    }

    /// Equal-value rows keep the wallet's canonical chain order. Yield
    /// providers follow chains and retain their declaration order.
    var sortIndex: Int {
        switch self {
        case .chain(let chain):
            return chain.index
        case .yield(let provider):
            return 10_000 + (DefiYieldProviderID.allCases.firstIndex(of: provider) ?? 0)
        }
    }
}

@MainActor
final class DefiMainViewModel: ObservableObject {
    @Published private var items = [DefiMainItem]()
    @Published var searchText: String = ""

    private let balanceService = DefiBalanceService()

    init() {}

    func filteredItems(in vault: Vault) -> [DefiMainItem] {
        items.filter { item in
            switch item {
            case .yield(let providerID):
                return matchesSearch(providerName(providerID))
            case .chain(let chain):
                let nameMatches = chain.name.localizedCaseInsensitiveContains(searchText)
                let tickerMatches = vault.nativeCoin(for: chain)?.ticker
                    .localizedCaseInsensitiveContains(searchText) ?? false
                return searchText.isEmpty || nameMatches || tickerMatches
            }
        }
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
            do {
                try Storage.shared.save()
            } catch {
                logger.error("Failed to persist DeFi provider migration: \(error.localizedDescription)")
            }
        }

        // Materialise the Earn selection an imported backup carries as plain
        // addresses into position rows, so the DeFi total below counts a
        // restored vault's deposits instead of showing zero until the user
        // opens the Solana chain screen. Idempotent and additive.
        do {
            try KaminoPositionStorageService().hydrateEnabledVaultsIfNeeded(for: vault)
        } catch {
            logger.error("Failed to hydrate Kamino selection: \(error.localizedDescription)")
        }

        let defiChains = vault.chainsWithCoins.filter { chain in
            vault.defiChains.contains(chain) && CoinAction.defiChains.contains(chain)
        }

        // A provider shows when it is enabled, the vault holds the provider's
        // chain, and its account (e.g. Circle MSCA) is provisioned. Account-less
        // providers are always provisioned, so the gate is uniform across providers.
        let visibleProviders = DefiYieldProviderID.allCases.filter { isProviderVisible($0, in: vault) }
        let unsortedItems = defiChains.map(DefiMainItem.chain) + visibleProviders.map(DefiMainItem.yield)

        items = DefiPositionOrdering.descending(
            unsortedItems,
            value: { displayedBalance(for: $0, in: vault) },
            tieBreak: \.sortIndex
        )
    }

    private func displayedBalance(for item: DefiMainItem, in vault: Vault) -> Decimal {
        switch item {
        case .chain(let chain):
            return balanceService.totalBalanceInFiat(for: chain, vault: vault)
        case .yield(let providerID):
            return balanceService.yieldBalanceFiatDecimal(for: providerID, vault: vault)
        }
    }

    private func isProviderVisible(_ id: DefiYieldProviderID, in vault: Vault) -> Bool {
        let provider = DefiYieldProviderFactory.make(id)
        guard vault.isDefiProviderEnabled(id), vault.chains.contains(provider.chain) else { return false }
        return provider.isAccountProvisioned(vault: vault)
    }

    private func providerName(_ id: DefiYieldProviderID) -> String {
        DefiYieldProviderFactory.make(id).presentation.providerNameKey.localized
    }

    private func matchesSearch(_ value: String) -> Bool {
        searchText.isEmpty || value.localizedCaseInsensitiveContains(searchText)
    }
}
