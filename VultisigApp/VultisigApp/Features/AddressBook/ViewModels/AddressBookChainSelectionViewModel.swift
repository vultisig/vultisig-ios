//
//  AddressBookChainSelectionViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/08/2025.
//

import SwiftUI

class AddressBookChainSelectionViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published private var chains: [AddressBookChainType] = []

    var filteredChains: [AddressBookChainType] {
        guard searchText.isNotEmpty else { return chains }
        return chains.filter { chainType in
            switch chainType {
            case .evm:
                return vaultChains.contains { $0.chain.name.localizedCaseInsensitiveContains(searchText) }
            case .chain(let coin):
                return coin.chain.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    let vaultChains: [CoinMeta]

    init(vaultChains: [CoinMeta]) {
        self.vaultChains = vaultChains
    }

    func setup() {
        var chains: [AddressBookChainType] = [.evm]
        chains += vaultChains
            .filter { $0.chain.type != .EVM}
            .map { .chain(coin: $0) }
        self.chains = chains
    }
}
