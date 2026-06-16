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
    case noon

    var id: String {
        switch self {
        case .chain(let chain): return chain.rawValue
        case .circle: return "circle"
        case .noon: return "noon"
        }
    }
}

@MainActor
final class DefiMainViewModel: ObservableObject {
    @Published private var chains = [Chain]()
    @Published private var showsCircle: Bool = false
    @Published private var showsNoon: Bool = false
    @Published var searchText: String = ""

    private let logic = VaultDetailLogic()

    init() {}

    func filteredItems(in vault: Vault) -> [DefiMainItem] {
        var prefix: [DefiMainItem] = []
        if showsCircle && matchesSearch(circleName) { prefix.append(.circle) }
        if showsNoon && matchesSearch(noonName) { prefix.append(.noon) }
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

        // Circle is no longer offered to new users: only show it for vaults
        // that already created a Circle account, so they can still withdraw.
        let hasCircleAccount = vault.circleWalletAddress?.isEmpty == false
        showsCircle = vault.isCircleEnabled
            && vault.chains.contains(.ethereum)
            && hasCircleAccount

        // Noon is a direct-EOA vault — no account gate, just the user toggle on
        // any Ethereum-enabled vault.
        showsNoon = vault.isNoonEnabled && vault.chains.contains(.ethereum)
    }

    private var circleName: String { "Circle" }
    private var noonName: String { "Noon" }

    private func matchesSearch(_ value: String) -> Bool {
        searchText.isEmpty || value.localizedCaseInsensitiveContains(searchText)
    }
}
