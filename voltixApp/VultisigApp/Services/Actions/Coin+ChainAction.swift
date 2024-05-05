//
//  Coin+ChainAction.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 01.05.2024.
//

import Foundation

extension Chain {

    var defaultActions: [CoinAction] {
        switch self {
        case .thorChain:
            return [.send, .swap]
        case .solana:
            return [.send]
        case .ethereum:
            return [.send, .swap]
        case .avalanche:
            return [.send, .swap]
        case .base:
            return [.send]
        case .blast:
            return [.send]
        case .arbitrum:
            return [.send]
        case .polygon:
            return [.send]
        case .optimism:
            return [.send]
        case .bscChain:
            return [.send, .swap]
        case .bitcoin:
            return [.send, .swap]
        case .bitcoinCash:
            return [.send, .swap]
        case .litecoin:
            return [.send, .swap]
        case .dogecoin:
            return [.send, .swap]
        case .dash:
            return [.send]
        case .gaiaChain:
            return [.send, .swap]
        case .kujira:
            return [.send]
        case .mayaChain:
            return [.send]
        case .cronosChain:
            return [.send]
        case .sui:
            return [.send]
        case .polkadot:
            return [.send]
        }
    }
}
