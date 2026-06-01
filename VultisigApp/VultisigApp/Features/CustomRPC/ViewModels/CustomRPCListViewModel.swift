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
    @Published private(set) var rows: [CustomRPCRow] = []

    private let store: CustomRPCStore

    init(store: CustomRPCStore = .shared) {
        self.store = store
    }

    func reload() {
        rows = CustomRPCSupportedChains.all.map { chain in
            CustomRPCRow(chain: chain, activeURL: store.url(for: chain))
        }
    }
}
