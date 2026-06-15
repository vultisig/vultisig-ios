//
//  CustomRPCSelectChainViewModel.swift
//  VultisigApp
//

import Foundation

/// Drives the Custom RPC chain-selection grid: exposes the supported chains
/// filtered by the search query and reports which chains already carry an
/// override so the grid can mark them with a pencil badge.
@MainActor
final class CustomRPCSelectChainViewModel: ObservableObject {
    @Published var searchText: String = ""

    private let store: CustomRPCStore

    init(store: CustomRPCStore = .shared) {
        self.store = store
    }

    /// Supported chains narrowed by `searchText`, matched case-insensitively
    /// against both the chain name and ticker so "eth", "ethereum" and "ETH"
    /// all surface Ethereum. An empty or whitespace-only query returns the full
    /// list.
    var filteredChains: [Chain] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isNotEmpty else { return CustomRPCSupportedChains.all }
        return CustomRPCSupportedChains.all.filter { chain in
            chain.name.localizedCaseInsensitiveContains(query) ||
            chain.ticker.localizedCaseInsensitiveContains(query)
        }
    }

    /// `true` when the chain carries a user override — drives the pencil badge.
    func hasOverride(_ chain: Chain) -> Bool {
        store.url(for: chain) != nil
    }
}
