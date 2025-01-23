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
        case .thorChain, .mayaChain:
            actions = [.send, .swap, .memo]
        case .solana, .ethereum, .avalanche, .base, .arbitrum, .polygon, .polygonV2, .optimism, .bscChain, .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash, .gaiaChain, .kujira, .zksync:
            actions = [.send, .swap]
        case .ton, .dydx:
            actions = [.send, .memo]
        case .blast, .cronosChain, .sui, .polkadot, .osmosis, .terra, .terraClassic, .noble, .akash, .ripple, .tron:
            actions = [.send]
        }
        return actions.filtered
    }
}
