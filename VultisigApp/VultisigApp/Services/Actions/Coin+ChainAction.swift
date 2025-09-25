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
        .thorChain, .mayaChain, .ethereum, .avalanche, .base, .arbitrum,.blast,.mantle,
        .polygon, .polygonV2, .optimism, .bscChain, .gaiaChain, .kujira, .zksync, .zcash, .ripple,
        .cronosChain
    ]
    
    static var memoChains: [Chain] = [
        .thorChain, .mayaChain, .ton, .dydx, .kujira, .gaiaChain, .osmosis,
        // THORChain LP supported chains
        .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .ethereum, .avalanche, .bscChain, .base, .ripple
    ]
}

extension Chain {
    var defaultActions: [CoinAction] {
        var actions: [CoinAction] = [.send] // always include send
        
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
        
        if CoinAction.swapChains.contains(self) {
            actions.append(.swap)
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
