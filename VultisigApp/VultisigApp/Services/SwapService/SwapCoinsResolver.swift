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
        let coins = allCoins.filter { coin in
            let commonProviders = fromCoin.swapProviders.filter { coin.swapProviders.contains($0) }
            return !commonProviders.isEmpty
        }
        .filter { $0 != fromCoin }
        .sorted()

        let selected = coins.contains(selectedToCoin) ? selectedToCoin : coins.first ?? .example
        return (coins, selected)
    }

    static func resolveProvider(fromCoin: Coin, toCoin: Coin) -> SwapProvider? {
        let commonProviders = fromCoin.swapProviders.filter { toCoin.swapProviders.contains($0) }
        return commonProviders.first // Pick the first available provider
    }
}
