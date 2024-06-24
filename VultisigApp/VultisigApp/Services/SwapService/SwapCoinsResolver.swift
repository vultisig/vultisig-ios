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

    static func resolveToCoins(fromCoin: Coin, allCoins: [Coin]) -> (coins: [Coin], selected: Coin) {
        let coins = allCoins
            .filter { $0.swapProviders.contains(where: fromCoin.swapProviders.contains) }
            .filter { $0 != fromCoin }
            .sorted()

        let selected = coins.first ?? .example

        return (coins, selected)
    }
}
