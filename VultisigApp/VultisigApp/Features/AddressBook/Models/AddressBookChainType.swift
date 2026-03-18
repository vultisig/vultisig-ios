//
//  AddressBookChainType.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/08/2025.
//

import Foundation

enum AddressBookChainType: Identifiable, Equatable, Hashable {
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
