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
    @Published private(set) var overriddenChains: Set<Chain> = []

    private let store: CustomRPCStore

    init(store: CustomRPCStore = .shared) {
        self.store = store
    }

    /// Re-reads which chains carry an override. Call on appear so the grid
    /// reflects edits made in the per-chain editor after navigating back.
    func refresh() {
        overriddenChains = Set(CustomRPCSupportedChains.all.filter { store.url(for: $0) != nil })
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
    /// Reads the `@Published` set so the grid re-renders after `refresh()`.
    func hasOverride(_ chain: Chain) -> Bool {
        overriddenChains.contains(chain)
    }
}
