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
        resolveFromCoins(allCoins: allCoins, providers: { $0.swapProviders })
    }

    /// `providers` resolves a coin's swap-provider list. The default uses the
    /// static `Coin.swapProviders`; the swap screen passes a closure backed by
    /// the live-pool-augmented set so previously-hidden `Available` tokens show.
    static func resolveFromCoins(
        allCoins: [Coin],
        providers: (Coin) -> [SwapProvider]
    ) -> ([Coin], selected: Coin) {
        let coins = allCoins
            .filter { !providers($0).isEmpty }
            .sorted()

        let selected = coins.first ?? .example

        return (coins, selected)
    }

    static func resolveToCoins(fromCoin: Coin, allCoins: [Coin], selectedToCoin: Coin) -> (coins: [Coin], selected: Coin) {
        resolveToCoins(fromCoin: fromCoin, allCoins: allCoins, selectedToCoin: selectedToCoin, providers: { $0.swapProviders })
    }

    static func resolveToCoins(
        fromCoin: Coin,
        allCoins: [Coin],
        selectedToCoin: Coin,
        providers: (Coin) -> [SwapProvider]
    ) -> (coins: [Coin], selected: Coin) {
        let fromProviders = providers(fromCoin)
        let coins = allCoins
            .filter { providers($0).contains(where: fromProviders.contains) }
            .filter { $0 != fromCoin }
            .sorted()

        let selected = coins.contains(selectedToCoin) ? selectedToCoin : coins.first ?? .example

        return (coins, selected)
    }

    static func resolveProvider(fromCoin: Coin, toCoin: Coin) -> SwapProvider? {
        return fromCoin.swapProviders.first(where: toCoin.swapProviders.contains)
    }

    static func resolveAllProviders(fromCoin: Coin, toCoin: Coin) -> [SwapProvider] {
        resolveAllProviders(fromCoin: fromCoin, toCoin: toCoin, providers: { $0.swapProviders })
    }

    /// Parametric variant: `providers` resolves each coin's provider list. The
    /// quote path passes a closure backed by the live-pool-augmented set (UNION
    /// with the static fallback) so a token made eligible by a live `Available`
    /// pool keeps its native provider through to quote/build — instead of being
    /// dropped by the static `Coin.swapProviders` and surfacing `routeUnavailable`.
    static func resolveAllProviders(
        fromCoin: Coin,
        toCoin: Coin,
        providers: (Coin) -> [SwapProvider]
    ) -> [SwapProvider] {
        let fromProviders = providers(fromCoin)
        let toProviders = providers(toCoin)
        var commonProviders = fromProviders.filter { toProviders.contains($0) }

        // If either coin is thorchain stagenet, remove mainnet thorchain provider to avoid mixing networks
        if toCoin.chain == .thorChainChainnet || fromCoin.chain == .thorChainChainnet {
            commonProviders = commonProviders.filter { $0 != .thorchain && $0 != .thorchainStagenet }
        }

        // If either coin is thorchain stagenet, remove mainnet and chainnet providers
        if toCoin.chain == .thorChainStagenet || fromCoin.chain == .thorChainStagenet {
            commonProviders = commonProviders.filter { $0 != .thorchain && $0 != .thorchainChainnet }
        }

        // If either coin is thorchain mainnet, remove stagenet providers to avoid mixing networks
        if toCoin.chain == .thorChain || fromCoin.chain == .thorChain {
            commonProviders = commonProviders.filter { $0 != .thorchainChainnet && $0 != .thorchainStagenet }
        }

        return commonProviders
    }
}
