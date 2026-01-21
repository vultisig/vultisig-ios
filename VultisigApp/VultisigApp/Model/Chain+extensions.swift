//
//  Chain+extensions.swift
//  VultisigApp
//
//  Created by Johnny Luo on 17/7/2024.
//

import Foundation

extension Chain {
    init?(name: String) {
        for chain in Chain.allCases where chain.name == name {
            self = chain
            return
        }
        return nil
    }
}

extension Chain {
    var canBuy: Bool {
        switch self {
        case .kujira, .blast, .terra, .terraClassic, .osmosis, .akash, .noble, .mayaChain, .thorChainStagenet, .hyperliquid, .sei:
            return false
        case .thorChain, .solana, .ethereum, .avalanche, .base, .arbitrum, .polygon, .polygonV2, .optimism, .bscChain, .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash, .cardano, .gaiaChain,
                .cronosChain, .sui, .polkadot, .zksync, .dydx, .ton, .ripple, .tron, .ethereumSepolia, .zcash, .mantle:
            return true
        }
    }
    var banxaBlockchainCode: String {
        switch self {
        case .bitcoin:
            return "BTC"
        case .bitcoinCash:
            return "BCH"
        case .litecoin:
            return "LTC"
        case .ethereum:
            return "ETH"
        case .bscChain:
            return "BSC"
        case .polygon:
            return "MATIC"
        case .avalanche:
            return "AVAX-C"
        case .arbitrum:
            return "ARB"
        case .thorChain:
            return "THORCHAIN"
        case .thorChainStagenet:
            return "THORCHAIN-STAGENET"
        case .solana:
            return "SOL"
        case .base:
            return "BASE"
        case .blast:
            return "BLAST"
        case .polygonV2:
            return "MATIC"
        case .optimism:
            return "OPTIMISM"
        case .dogecoin:
            return "DOGE"
        case .dash:
            return "DASH"
        case .cardano:
            return "ADA"
        case .gaiaChain:
            return "ATOM"
        case .kujira:
            return "KUJIRA"
        case .mayaChain:
            return "MAYACHAIN"
        case .cronosChain:
            return "CRO"
        case .sui:
            return "SUI"
        case .polkadot:
            return "DOT"
        case .zksync:
            return "ZKSYNC"
        case .dydx:
            return "DYDX"
        case .ton:
            return "TON"
        case .osmosis:
            return "OSMOSIS"
        case .terra:
            return "LUNA"
        case .terraClassic:
            return "LUNC"
        case .noble:
            return "NOBLE"
        case .ripple:
            return "XRP"
        case .akash:
            return "AKASH"
        case .tron:
            return "TRON"
        case .ethereumSepolia:
            return "ETH"
        case .zcash:
            return "ZEC"
        case .mantle:
            return "MNT"
        case .hyperliquid:
            return "HYPE"
        case .sei:
            return "SEI"
        }
    }
}
