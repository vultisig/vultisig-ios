//
//  SwapCoinsResolver.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 24.06.2024.
//

import Foundation

struct SwapCoinsResolver {

    private init() { }

    static func resolveFromCoins(allCoins: [Coin]) -> [Coin] {
        return allCoins
            .filter { $0.isSwapSupported }
            .sorted(by: { $0.rawBalance > $1.rawBalance })
    }

    static func resolveToCoins(fromCoin: Coin, allCoins: [Coin]) -> [Coin] {
        return allCoins.filter { coin in
            coin.swapProviders.contains(where: fromCoin.swapProviders.contains)
        }
    }
}
