//
//  Coin+Swaps.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 11.06.2024.
//

import Foundation

extension Coin {

    var thorswapMultiplier: Decimal {
        switch chain {
        case .mayaChain:
            return 1e10
        default:
            return 1e8
        }
    }

    var isSwapSupported: Bool {
        return !swapProviders.isEmpty
    }

    var swapProviders: [SwapProvider] {
        switch chain {
        case .mayaChain, .dash, .kujira:
            return [.mayachain]
        case .ethereum:
            let defaultProviders: [SwapProvider] = [
                .oneinch(chain),
                .lifi
            ]

            var providers: [SwapProvider] = []

            if thorEthTokens.contains(ticker) {
                providers.append(.thorchain)
            }

            if mayaEthTokens.contains(ticker) {
                providers.append(.mayachain)
            }

            return providers + defaultProviders
        case .bscChain:
            if thorBscTokens.contains(ticker) {
                return [.thorchain, .oneinch(chain), .lifi]
            } else {
                return [.oneinch(chain), .lifi]
            }
        case .avalanche:
            if thorAvaxTokens.contains(ticker) {
                return [.thorchain, .oneinch(chain), .lifi]
            } else {
                return [.oneinch(chain), .lifi]
            }
        case .arbitrum:
            if mayaArbTokens.contains(ticker) {
                return [.mayachain, .oneinch(chain), .lifi]
            } else {
                return [.oneinch(chain), .lifi]
            }
        case .optimism, .polygon, .polygonV2, .base, .zksync:
            return [.oneinch(chain), .lifi]
        case .thorChain:
            return [.thorchain, .mayachain]
        case .bitcoin:
            return [.thorchain, .mayachain]
        case .dogecoin, .bitcoinCash, .litecoin, .gaiaChain:
            return [.thorchain]
        case .blast, .solana:
            return [.lifi]
        case .sui, .polkadot, .dydx, .cronosChain, .ton, .osmosis, .terra, .terraClassic, .noble, .ripple, .akash, .tron:
            return []
        }
    }

    var isLifiFeesSupported: Bool {
        switch chain.chainType {
        case .EVM:
            return true
        default:
            return false
        }
    }
}

private extension Coin {

    var mayaEthTokens: [String] {
        return ["ETH"]
    }

    var mayaArbTokens: [String] {
        return ["ETH"]
    }

    var thorEthTokens: [String] {
        return ["ETH", "USDT", "USDC", "WBTC", "THOR", "XRUNE", "DAI", "LUSD", "GUSD", "VTHOR", "USDP", "LINK", "WSTETH", "TGT", "AAVE", "FOX", "DPI", "SNX"]
    }

    var thorBscTokens: [String] {
        return ["BNB", "USDT", "USDC"]
    }

    var thorAvaxTokens: [String] {
        return ["AVAX", "USDC", "USDT", "SOL"]
    }
}
