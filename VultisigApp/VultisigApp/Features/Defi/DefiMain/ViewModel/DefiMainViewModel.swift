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

    private var circleName: String { "Circle" }

    private func matchesSearch(_ value: String) -> Bool {
        searchText.isEmpty || value.localizedCaseInsensitiveContains(searchText)
    }
}
