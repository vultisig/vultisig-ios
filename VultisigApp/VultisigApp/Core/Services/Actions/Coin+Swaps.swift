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
            return pow(10, decimals)
        default:
            return 1e8
        }
    }

    var isSwapSupported: Bool {
        return !swapProviders.isEmpty
    }

    var swapProviders: [SwapProvider] {
        // SwapKit is opt-in behind the Settings → Advanced → "SwapKit"
        // toggle. When the flag is off, drop `.swapkit` from every chain's
        // provider list — ranking falls back to the other providers exactly
        // as before the SwapKit integration shipped. Single point of
        // gating: every chain's switch arm below carries `.swapkit` as if
        // unconditionally enabled, and this filter prunes when needed.
        let providers = naturalSwapProviders
        guard !SwapKitConfig.isFeatureEnabled else { return providers }
        return providers.filter { $0 != .swapkit }
    }

    private var naturalSwapProviders: [SwapProvider] {
        switch chain {
        case .mayaChain, .dash, .kujira:
            return [.mayachain]
        case .ethereum:
            let defaultProviders: [SwapProvider] = [
                .oneinch(chain),
                .lifi,
                .kyberswap(chain),
                .swapkit
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
                return [.thorchain, .oneinch(chain), .lifi, .kyberswap(chain), .swapkit]
            } else {
                return [.oneinch(chain), .lifi, .kyberswap(chain), .swapkit]
            }
        case .avalanche:
            if thorAvaxTokens.contains(ticker) {
                return [.thorchain, .oneinch(chain), .lifi, .kyberswap(chain), .swapkit]
            } else {
                return [.oneinch(chain), .lifi, .kyberswap(chain), .swapkit]
            }
        case .arbitrum:
            if mayaArbTokens.contains(ticker) {
                return [.mayachain, .oneinch(chain), .lifi, .kyberswap(chain), .swapkit]
            } else {
                return [.oneinch(chain), .lifi, .kyberswap(chain), .swapkit]
            }
        case .base:
            if thorBaseTokens.contains(ticker) {
                return [.thorchain, .oneinch(chain), .lifi, .swapkit] // KyberSwap not supported
            }
            return [.oneinch(chain), .lifi, .swapkit] // KyberSwap not supported
        case .optimism, .polygon, .polygonV2:
            return [.lifi, .oneinch(chain), .kyberswap(chain), .swapkit] // KyberSwap supported
        case .mantle:
            // `.swapkit` is included unconditionally — eligibility per chain
            // is gated dynamically by `SwapKitProviderCache.isEnabled`
            // against the cached `/v3/providers.enabledChainIds`. If
            // SwapKit lights up Mantle later, no iOS release needed.
            return [.lifi, .oneinch(chain), .kyberswap(chain), .swapkit]
        case .zksync:
            return [.oneinch(chain), .lifi, .swapkit] // KyberSwap not supported on zkSync
        case .blast:
            return [.lifi, .swapkit] // KyberSwap not supported on Blast
        case .thorChain:
            return [.thorchain, .mayachain]
        case .thorChainChainnet:
            return [.thorchainChainnet]
        case .thorChainStagenet:
            return [.thorchainStagenet]
        case .bitcoin:
            return [.thorchain, .mayachain]
        case .dogecoin, .bitcoinCash, .litecoin, .gaiaChain:
            return [.thorchain]
        case .solana:
            // Phase 1 chain — `.swapkit` enables EVM↔Solana and Solana↔EVM
            // routes via NEAR Intents / Chainflip / etc.
            return [.thorchain, .lifi, .swapkit]
        case .hyperliquid:
            return [.lifi]
        case .cronosChain:
            return [.lifi]
        case .zcash:
            return [.mayachain]
        case .ripple:
            return [.thorchain]
        case .tron:
            return [.thorchain]
        case .sui, .polkadot, .dydx, .ton, .osmosis, .terra, .terraClassic, .noble, .akash, .ethereumSepolia, .cardano, .sei, .qbtc, .bittensor:
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
        return ["ETH", "ARB", "USDC", "YUM", "TGT", "GLD", "USDT", "PEPE"]
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
