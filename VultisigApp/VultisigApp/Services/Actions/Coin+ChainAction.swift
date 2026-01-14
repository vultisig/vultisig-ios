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
        .thorChain, .thorChainStagenet, .mayaChain, .ethereum, .avalanche, .base, .arbitrum,.blast,.mantle,.hyperliquid,
        .polygon, .polygonV2, .optimism, .bscChain, .gaiaChain, .kujira, .zksync, .zcash, .ripple,
        .cronosChain, .tron
    ]
    
    static var memoChains: [Chain] = [
        .thorChain, .thorChainStagenet, .mayaChain, .ton, .dydx, .kujira, .gaiaChain, .osmosis,
        // THORChain LP supported chains
        .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .ethereum, .avalanche, .bscChain, .base, .ripple
    ]
    
    static var defiChains: [Chain] = [
        .thorChain,
        .mayaChain,
        .tron
    ]
}

extension Chain {
    var defaultActions: [CoinAction] {
        
        var actions: [CoinAction] = []
        
        if CoinAction.swapChains.contains(self) {
            actions.append(.swap)
        }
        actions.append(.send) // always include send
        let hasBuyEnabledSet = UserDefaults.standard.value(forKey: "BuyEnabled")
        // when hasBuyEnabledSet has not been set , set it to true
        if hasBuyEnabledSet == nil {
            UserDefaults.standard.set(true, forKey: "BuyEnabled")
        }
        let enableBuy = UserDefaults.standard.bool(forKey: "BuyEnabled")
        if enableBuy {
            actions.append(.buy)
        }
        let enableSell = UserDefaults.standard.bool(forKey: "SellEnabled")
        if enableSell {
            actions.append(.sell)
        }
        
        if CoinAction.memoChains.contains(self) {
            actions.append(.memo)
        }
        
        actions.append(.receive)
        
        return actions.filtered
    }
}

extension Array where Element == CoinAction {
    var filtered: [CoinAction] {
        if !SwapFeatureGate.canSwap() {
            return filter { $0 != .swap }
        } else {
            return self
        }
    }
}
