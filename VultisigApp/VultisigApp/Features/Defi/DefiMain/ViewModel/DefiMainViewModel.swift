//
//  DefiMainViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 16/10/2025.
//

import Foundation

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

    init() {}

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
        let defiChains = vault.chainsWithCoins.filter { chain in
            vault.defiChains.contains(chain) && CoinAction.defiChains.contains(chain)
        }

        chains = logic.sortedChains(
            chains: defiChains,
            value: { vault.coins(for: $0).totalDefiBalanceInFiatDecimal }
        )

        // Circle is no longer offered to new users: only show it for vaults
        // that already created a Circle account, so they can still withdraw.
        let hasCircleAccount = vault.circleWalletAddress?.isEmpty == false
        showsCircle = vault.isCircleEnabled
            && vault.chains.contains(.ethereum)
            && hasCircleAccount
    }

    private var circleName: String { "Circle" }

    private func matchesSearch(_ value: String) -> Bool {
        searchText.isEmpty || value.localizedCaseInsensitiveContains(searchText)
    }
}
