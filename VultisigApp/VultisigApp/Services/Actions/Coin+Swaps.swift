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
            if thorEthTokens.contains(ticker) {
                return [.thorchain, .oneinch(chain)]
            } else {
                return [.oneinch(chain)]
            }
        case .bscChain:
            if thorBscTokens.contains(ticker) {
                return [.thorchain, .oneinch(chain)]
            } else {
                return [.oneinch(chain)]
            }
        case .avalanche:
            if thorAvaxTokens.contains(ticker) {
                return [.thorchain, .oneinch(chain)]
            } else {
                return [.oneinch(chain)]
            }
        case .base, .optimism, .polygon:
            return [.oneinch(chain)]
        case .thorChain, .bitcoin, .dogecoin, .bitcoinCash, .litecoin, .gaiaChain:
            return [.thorchain]
        case .solana, .sui, .polkadot, .dydx, .arbitrum, .blast, .cronosChain, .zksync:
            return []
        }
    }
}

private extension Coin {

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
