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
        .polygon, .polygonV2, .optimism, .bscChain, .gaiaChain, .kujira, .zksync, .zcash, .ripple
    ]
    
    static var memoChains: [Chain] = [
        .thorChain, .mayaChain, .ton, .dydx, .kujira, .gaiaChain, .osmosis
    ]
}

extension Chain {
    
    var defaultActions: [CoinAction] {
        var actions: [CoinAction] = [.send] // always include send
#if os(iOS)
        let hasMoonPayEnabledSet = UserDefaults.standard.value(forKey: "moonpayBuyEnabled")
        // when moonpayBuyEnabled has not been set , set it to true
        if hasMoonPayEnabledSet == nil {
            UserDefaults.standard.set(true, forKey: "moonpayBuyEnabled")
        }
        let enableMoonpayBuy = UserDefaults.standard.bool(forKey: "moonpayBuyEnabled")
        if enableMoonpayBuy {
            actions.append(.buy)
        }
        let enableMoonpaySell = UserDefaults.standard.bool(forKey: "moonpaySellEnabled")
        if enableMoonpaySell {
            actions.append(.sell)
        }
#endif
        if CoinAction.swapChains.contains(self) {
            actions.append(.swap)
        }
        if CoinAction.memoChains.contains(self) {
            actions.append(.memo)
        }
        
        return actions.filtered
    }
}
