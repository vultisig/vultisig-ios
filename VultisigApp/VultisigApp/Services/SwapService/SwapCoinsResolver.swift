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

        // If either coin is thorchain stagenet, remove mainnet thorchain provider to avoid mixing networks
        if toCoin.chain == .thorChainStagenet || fromCoin.chain == .thorChainStagenet {
            commonProviders = commonProviders.filter { $0 != .thorchain && $0 != .thorchainStagenet2 }
        }

        // If either coin is thorchain stagenet-2, remove mainnet and stagenet-1 providers
        if toCoin.chain == .thorChainStagenet2 || fromCoin.chain == .thorChainStagenet2 {
            commonProviders = commonProviders.filter { $0 != .thorchain && $0 != .thorchainStagenet }
        }

        // If either coin is thorchain mainnet, remove stagenet providers to avoid mixing networks
        if toCoin.chain == .thorChain || fromCoin.chain == .thorChain {
            commonProviders = commonProviders.filter { $0 != .thorchainStagenet && $0 != .thorchainStagenet2 }
        }

        return commonProviders
    }
}
