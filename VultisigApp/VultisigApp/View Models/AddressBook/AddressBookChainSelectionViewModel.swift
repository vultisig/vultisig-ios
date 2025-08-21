//
//  AddressBookChainSelectionViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/08/2025.
//

import SwiftUI

enum AddressBookChainType: Identifiable, Equatable {
    case evm
    case chain(coin: CoinMeta)
    
    init(coinMeta: CoinMeta) {
        switch coinMeta.chain.type {
        case .EVM:
            self = .evm
        default:
            self = .chain(coin: coinMeta)
        }
    }
    
    var id: String { name }
    
    var name: String {
        switch self {
        case .evm:
            "evmChains".localized
        case .chain(let coin):
            coin.chain.name
        }
    }
    
    var icon: String {
        switch self {
        case .evm:
            Chain.ethereum.logo
        case .chain(let coin):
            coin.chain.logo
        }
    }
    
    var chain: Chain {
        switch self {
        case .evm:
            return .ethereum
        case .chain(let coin):
            return coin.chain
        }
    }
}

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
