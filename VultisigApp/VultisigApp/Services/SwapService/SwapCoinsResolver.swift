//
//  SwapCoinsResolver.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 24.06.2024.
//

import Foundation

struct SwapCoinsResolver {

    private init() { }

    static func resolveFromCoins(allCoins: [Coin]) -> ([Coin], selected: Coin) {
        let coins = allCoins
            .filter { $0.isSwapSupported }
            .sorted()

        let selected = coins.first ?? .example

        return (coins, selected)
    }

    static func resolveToCoins(fromCoin: Coin, allCoins: [Coin], selectedToCoin: Coin) -> (coins: [Coin], selected: Coin) {
        
        let coins = allCoins
            .filter { $0.swapProviders.contains(where: fromCoin.swapProviders.contains) }
            .filter { $0 != fromCoin }
            .sorted()

        let selected = coins.contains(selectedToCoin) ? selectedToCoin : coins.first ?? .example

        return (coins, selected)
    }

    static func resolveProvider(fromCoin: Coin, toCoin: Coin) -> SwapProvider? {
        return fromCoin.swapProviders.first(where: toCoin.swapProviders.contains)
    }
    
    static func resolveAllProviders(fromCoin: Coin, toCoin: Coin) -> [SwapProvider] {
        var commonProviders = fromCoin.swapProviders.filter { toCoin.swapProviders.contains($0) }
        
        // If toCoin is thorchain stagenet, remove mainnet thorchain provider to avoid mixing networks
        if toCoin.chain == .thorChainStagenet {
            commonProviders = commonProviders.filter { $0 != .thorchain }
        }
        
        // If toCoin is thorchain mainnet, remove stagenet provider to avoid mixing networks
        if toCoin.chain == .thorChain {
            commonProviders = commonProviders.filter { $0 != .thorchainStagenet }
        }
        
        // If fromCoin is thorchain stagenet, remove mainnet thorchain provider
        if fromCoin.chain == .thorChainStagenet {
            commonProviders = commonProviders.filter { $0 != .thorchain }
        }
        
        // If fromCoin is thorchain mainnet, remove stagenet provider
        if fromCoin.chain == .thorChain {
            commonProviders = commonProviders.filter { $0 != .thorchainStagenet }
        }
        
        return commonProviders
    }
}
