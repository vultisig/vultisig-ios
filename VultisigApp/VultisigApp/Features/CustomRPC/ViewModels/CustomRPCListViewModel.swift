//
//  CustomRPCListViewModel.swift
//  VultisigApp
//

import Foundation

/// Display state for one chain row in the custom-RPC list.
struct CustomRPCRow: Identifiable, Hashable {
    let chain: Chain
    let activeURL: String?

    var id: String { chain.rawValue }
    var isCustom: Bool { activeURL != nil }
}

@MainActor
final class CustomRPCListViewModel: ObservableObject {
    @Published private(set) var allRows: [CustomRPCRow] = []
    @Published var searchText: String = ""

    private let store: CustomRPCStore

    init(store: CustomRPCStore = .shared) {
        self.store = store
    }

    /// Rows narrowed by `searchText`, matched case-insensitively against both the
    /// chain name and ticker so "eth", "ethereum" and "ETH" all surface Ethereum.
    /// An empty or whitespace-only query returns the full list.
    var filteredRows: [CustomRPCRow] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isNotEmpty else { return allRows }
        return allRows.filter { row in
            row.chain.name.localizedCaseInsensitiveContains(query) ||
            row.chain.ticker.localizedCaseInsensitiveContains(query)
        }
    }

    func reload() {
        allRows = CustomRPCSupportedChains.all.map { chain in
            CustomRPCRow(chain: chain, activeURL: store.url(for: chain))
        }
    }
}
