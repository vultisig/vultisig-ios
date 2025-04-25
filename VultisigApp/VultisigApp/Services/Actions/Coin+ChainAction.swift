//
//  Coin+ChainAction.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 01.05.2024.
//

import Foundation

extension CoinAction {
    
    static var swapChains: [Chain] = [
        .solana,.bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash,
        .thorChain, .mayaChain, .ethereum, .avalanche, .base, .arbitrum,
        .polygon, .polygonV2, .optimism, .bscChain, .gaiaChain, .kujira, .zksync
    ]
    
    static var memoChains: [Chain] = [
        .thorChain, .mayaChain, .ton, .dydx, .kujira, .gaiaChain
    ]
}

extension Chain {
    
    var defaultActions: [CoinAction] {
        var actions: [CoinAction] = [.send] // always include send
        
        if CoinAction.swapChains.contains(self) {
            actions.append(.swap)
        }
        if CoinAction.memoChains.contains(self) {
            actions.append(.memo)
        }
        
        return actions.filtered
    }
}
