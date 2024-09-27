//
//  Coin+ChainAction.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 01.05.2024.
//

import Foundation

extension Chain {
    var defaultActions: [CoinAction] {
        let actions: [CoinAction]
        switch self {
        case .thorChain:
            actions = [.send, .swap, .memo]
        case .solana:
            actions = [.send]
        case .ethereum:
            actions = [.send, .swap]
        case .avalanche:
            actions = [.send, .swap]
        case .base:
            actions = [.send, .swap]
        case .blast:
            actions = [.send]
        case .arbitrum:
            actions = [.send, .swap]
        case .polygon:
            actions = [.send, .swap]
        case .optimism:
            actions = [.send, .swap]
        case .bscChain:
            actions = [.send, .swap]
        case .bitcoin:
            actions = [.send, .swap]
        case .bitcoinCash:
            actions = [.send, .swap]
        case .litecoin:
            actions = [.send, .swap]
        case .dogecoin:
            actions = [.send, .swap]
        case .dash:
            actions = [.send, .swap]
        case .gaiaChain:
            actions = [.send, .swap]
        case .kujira:
            actions = [.send, .swap]
        case .mayaChain:
            actions = [.send, .swap, .memo]
        case .cronosChain:
            actions = [.send]
        case .sui:
            actions = [.send]
        case .polkadot:
            actions = [.send]
        case .zksync:
            actions = [.send, .swap]
        case .dydx:
            actions = [.send, .memo]
        }
        return actions.filtered
    }
}
