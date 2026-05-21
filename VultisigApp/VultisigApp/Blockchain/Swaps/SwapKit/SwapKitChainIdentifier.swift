//
//  SwapKitChainIdentifier.swift
//  VultisigApp
//
//  Translation from the Vultisig `Chain` enum to the chainId string SwapKit's
//  `/track` endpoint expects. The table mirrors the canonical chain table in
//  `swapkit-spike/api-contract.md` — EVM chains use the decimal chainId,
//  non-EVM chains use SwapKit's slug.
//
//  Kept separate from `SwapKitService.chainPrefix` because that function maps
//  to the *asset prefix* (e.g. `ETH`, `ARB`, `BTC`) — `/track` needs the
//  numeric/slug chainId instead, which only overlaps for a couple of chains.
//

import Foundation

enum SwapKitChainIdentifier {
    /// Returns the chainId string SwapKit's `/track` endpoint expects, or
    /// `nil` for chains that are not part of the SwapKit route catalogue.
    /// `nil` is the signal to skip tracking — the caller surfaces a deep-link
    /// fallback rather than attempting polling against an unknown chain.
    static func chainId(for chain: Chain) -> String? {
        switch chain {
        case .ethereum:
            return "1"
        case .arbitrum:
            return "42161"
        case .avalanche:
            return "43114"
        case .base:
            return "8453"
        case .bscChain:
            return "56"
        case .polygon, .polygonV2:
            return "137"
        case .optimism:
            return "10"
        case .blast:
            return "81457"
        case .zksync:
            return "324"
        case .tron:
            return "728126428"
        case .cardano:
            return "cardano"
        case .ton:
            return "ton"
        case .solana:
            return "solana"
        case .bitcoin:
            return "bitcoin"
        case .bitcoinCash:
            return "bitcoincash"
        case .litecoin:
            return "litecoin"
        case .ripple:
            return "ripple"
        case .gaiaChain:
            return "cosmoshub-4"
        case .dash:
            return "dash"
        case .zcash:
            return "zcash"
        case .sui:
            return "sui"
        case .dogecoin:
            return "dogecoin"
        case .kujira:
            return "kaiyo-1"
        case .mayaChain:
            return "mayachain-mainnet-v1"
        case .thorChain, .thorChainChainnet, .thorChainStagenet:
            return "thorchain-1"
        default:
            return nil
        }
    }
}
