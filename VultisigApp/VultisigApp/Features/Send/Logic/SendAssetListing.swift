//
//  SendAssetListing.swift
//  VultisigApp
//

import Foundation

/// Which of the vault's coins the Send asset list shows.
enum SendAssetListRule {
    /// The search text in the form the list matches against.
    static func query(from searchText: String) -> String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func isSendable(_ coin: Coin, sendableChains: Set<Chain>) -> Bool {
        sendableChains.contains(coin.chain) && !coin.isDefiOnly
    }

    /// A search spans every chain; without one the chain filter applies.
    static func matches(_ coin: Coin, filter: SendChainFilter, query: String) -> Bool {
        guard !query.isEmpty else { return filter.includes(coin.chain) }
        return coin.ticker.lowercased().contains(query) || coin.chain.displayName.lowercased().contains(query)
    }
}

/// The asset list and carousel order, rebuilt only when their inputs change.
struct SendAssetListing {
    struct Row {
        let coin: Coin
        let fiat: Decimal
    }

    /// The filter the rows were built for.
    let filter: SendChainFilter
    let rows: [Row]
    let chains: [Chain]

    /// Everything the listing depends on that changes while the asset step is shown.
    struct Inputs: Equatable {
        struct CoinBalance: Equatable {
            let id: String
            let rawBalance: String
        }

        let filter: SendChainFilter
        let query: String
        let selectedCoinID: String
        let coins: [CoinBalance]
    }

    /// The vault's sendable coins, richest first with the selected coin on top,
    /// and the sendable chains, largest holding first. A search spans every
    /// chain; without one the chain filter applies. Each coin's fiat value is
    /// read once, in one currency, for both orders.
    @MainActor
    static func make(vault: Vault, inputs: Inputs) -> SendAssetListing {
        let currency = SettingsCurrency.current
        let chains = vault.chains
        let sendableChains = Set(chains)
        var holdings: [Chain: Decimal] = [:]
        var rows: [Row] = []
        for coin in vault.coins where SendAssetListRule.isSendable(coin, sendableChains: sendableChains) {
            let fiat = RateProvider.shared.fiatBalance(value: coin.combinedBalanceDecimal, coin: coin, currency: currency)
            holdings[coin.chain, default: 0] += fiat
            if SendAssetListRule.matches(coin, filter: inputs.filter, query: inputs.query) {
                rows.append(Row(coin: coin, fiat: fiat))
            }
        }
        rows.sort { lhs, rhs in
            if lhs.fiat != rhs.fiat { return lhs.fiat > rhs.fiat }
            if lhs.coin.ticker != rhs.coin.ticker { return lhs.coin.ticker < rhs.coin.ticker }
            return lhs.coin.chain.index < rhs.coin.chain.index
        }
        if let selectedIndex = rows.firstIndex(where: { $0.coin.id == inputs.selectedCoinID }) {
            rows.insert(rows.remove(at: selectedIndex), at: 0)
        }
        return SendAssetListing(filter: inputs.filter, rows: rows, chains: sortedByHoldings(chains, holdings: holdings))
    }

    /// Ties keep the vault's order so the row stays put until a balance changes.
    private static func sortedByHoldings(_ chains: [Chain], holdings: [Chain: Decimal]) -> [Chain] {
        chains.enumerated()
            .sorted { lhs, rhs in
                let lhsHolding = holdings[lhs.element] ?? 0
                let rhsHolding = holdings[rhs.element] ?? 0
                if lhsHolding != rhsHolding { return lhsHolding > rhsHolding }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
