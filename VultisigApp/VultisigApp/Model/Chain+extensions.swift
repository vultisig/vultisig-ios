//
//  Chain+extensions.swift
//  VultisigApp
//
//  Created by Johnny Luo on 17/7/2024.
//

import Foundation

extension Chain {
    init?(name: String) {
        for chain in Chain.allCases where chain.name == name {
            self = chain
            return
        }
        return nil
    }
}

extension Chain {
    var canBuy: Bool {
        switch self {
        case .kujira, .blast, .terra, .terraClassic, .osmosis, .akash, .noble, .mayaChain, .thorChainChainnet, .thorChainStagenet, .hyperliquid, .sei, .qbtc, .bittensor:
            return false
        case .thorChain, .solana, .ethereum, .avalanche, .base, .arbitrum, .polygon, .polygonV2, .optimism, .bscChain, .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash, .cardano, .gaiaChain,
                .cronosChain, .sui, .polkadot, .zksync, .dydx, .ton, .ripple, .tron, .ethereumSepolia, .zcash, .mantle:
            return true
        }
    }
}
