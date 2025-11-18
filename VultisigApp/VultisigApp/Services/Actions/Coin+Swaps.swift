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
                .lifi,
                .kyberswap(chain),
            ]
            
            var providers: [SwapProvider] = []
            
            if thorEthTokens.contains(ticker) {
                providers.append(.thorchain)
                providers.append(.thorchainStagenet)
            }
            
            if mayaEthTokens.contains(ticker) {
                providers.append(.mayachain)
            }
            
            return providers + defaultProviders
        case .bscChain:
            if thorBscTokens.contains(ticker) {
                return [.thorchain, .thorchainStagenet, .oneinch(chain), .lifi,  .kyberswap(chain)]
            } else {
                return [.oneinch(chain), .lifi,.kyberswap(chain) ]
            }
        case .avalanche:
            if thorAvaxTokens.contains(ticker) {
                return [.thorchain, .thorchainStagenet, .oneinch(chain), .lifi, .kyberswap(chain)]
            } else {
                return [.oneinch(chain), .lifi,.kyberswap(chain)]
            }
        case .arbitrum:
            if mayaArbTokens.contains(ticker) {
                return [.mayachain, .oneinch(chain), .lifi, .kyberswap(chain), ]
            } else {
                return [.oneinch(chain), .lifi, .kyberswap(chain), ]
            }
        case .base:
            if thorBaseTokens.contains(ticker) {
                return [.thorchain, .thorchainStagenet, .oneinch(chain), .lifi] // KyberSwap not supported
            }
            return [.oneinch(chain), .lifi] // KyberSwap not supported
        case .optimism, .polygon, .polygonV2, .mantle:
            return [.lifi, .oneinch(chain), .kyberswap(chain)] // KyberSwap supported
        case .zksync:
            return [.oneinch(chain), .lifi] // KyberSwap not supported on zkSync
        case .blast:
            return [.lifi] // KyberSwap not supported on Blast
        case .thorChain:
            return [.thorchain, .mayachain]
        case .thorChainStagenet:
            return [.thorchainStagenet]
        case .bitcoin:
            return [.thorchain, .thorchainStagenet, .mayachain]
        case .dogecoin, .bitcoinCash, .litecoin, .gaiaChain:
            return [.thorchain, .thorchainStagenet]
        case .solana:
            return [.lifi]
        case .hyperliquid:
            return [.lifi]
        case .cronosChain:
            return [.lifi]
        case .zcash:
            return [.mayachain]
        case .ripple:
            return [.thorchain, .thorchainStagenet]
        case .tron:
            return [.thorchain, .thorchainStagenet]
        case .sui, .polkadot, .dydx, .ton, .osmosis, .terra, .terraClassic, .noble, .akash, .ethereumSepolia, .cardano, .sei:
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
        return ["ETH","USDC"]
    }
    
    var mayaArbTokens: [String] {
        return ["ETH","ARB","USDC","YUM","TGT","GLD","USDT","PEPE"]
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
