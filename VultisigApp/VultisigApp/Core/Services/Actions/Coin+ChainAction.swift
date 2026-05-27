//
//  Coin+ChainAction.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 01.05.2024.
//

import Foundation

extension CoinAction {

    static var memoChains: [Chain] = [
        .thorChain, .thorChainChainnet, .thorChainStagenet, .mayaChain, .ton, .dydx, .kujira, .gaiaChain, .osmosis,
        // THORChain LP supported chains
        .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .ethereum, .avalanche, .bscChain, .base, .ripple
    ]

    static var defiChains: [Chain] = [
        .thorChain,
        .mayaChain,
        .tron,
        .terra,
        .terraClassic
    ]

}

extension Chain {
    var defaultActions: [CoinAction] {

        var actions: [CoinAction] = []

        if self.isSwapAvailable {
            actions.append(.swap)
        }
        actions.append(.send) // always include send

        actions.append(.buy)
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
