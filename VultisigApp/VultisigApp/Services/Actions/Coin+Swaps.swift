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
                .kyberswap(chain),
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
                return [.thorchain, .kyberswap(chain), .oneinch(chain), .lifi]
            } else {
                return [.kyberswap(chain), .oneinch(chain), .lifi]
            }
        case .avalanche:
            if thorAvaxTokens.contains(ticker) {
                return [.thorchain, .kyberswap(chain), .oneinch(chain), .lifi]
            } else {
                return [.kyberswap(chain), .oneinch(chain), .lifi]
            }
        case .arbitrum:
            if mayaArbTokens.contains(ticker) {
                return [.mayachain, .oneinch(chain), .lifi, .kyberswap(chain), ]
            } else {
                return [.oneinch(chain), .lifi, .kyberswap(chain), ]
            }
        case .base:
            if thorBaseTokens.contains(ticker) {
                return [.thorchain, .oneinch(chain), .lifi] // KyberSwap not supported
            }
            return [.oneinch(chain), .lifi] // KyberSwap not supported
        case .optimism, .polygon, .polygonV2:
            return [.kyberswap(chain), .oneinch(chain), .lifi] // KyberSwap supported
        case .zksync:
            return [.oneinch(chain), .lifi] // KyberSwap not supported on zkSync
        case .blast:
            return [.lifi] // KyberSwap not supported on Blast
        case .thorChain:
            return [.thorchain, .mayachain]
        case .bitcoin:
            return [.thorchain, .mayachain]
        case .dogecoin, .bitcoinCash, .litecoin, .gaiaChain:
            return [.thorchain]
        case .solana:
            return [.lifi]
        case .cronosChain:
            return [.lifi]
        case .zcash:
            return [.mayachain]
        case .ripple:
            return [.thorchain]
        case .sui, .polkadot, .dydx, .ton, .osmosis, .terra, .terraClassic, .noble, .akash, .tron, .ethereumSepolia, .cardano:
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
        return ["ETH", "USDC"]
    }
    
    var mayaArbTokens: [String] {
        return ["ETH"]
    }
    
    var thorEthTokens: [String] {
        return ["ETH", "USDT", "USDC", "WBTC", "THOR", "XRUNE", "DAI", "LUSD", "GUSD", "VTHOR", "USDP", "LINK", "WSTETH", "TGT", "AAVE", "FOX", "DPI", "SNX", "vTHOR"]
    }
    
    var thorBscTokens: [String] {
        return ["BNB", "USDT", "USDC"]
    }
    
    var thorBaseTokens: [String] {
        return ["ETH", "USDC", "CBBTC"]
    }
    
    var thorAvaxTokens: [String] {
        return ["AVAX", "USDC", "USDT", "SOL"]
    }
}
