//
//  BlockaidChainIdentifier.swift
//  VultisigApp
//

enum BlockaidChainIdentifier {
    static func name(for chain: Chain) -> String? {
        switch chain {
        case .arbitrum: return "arbitrum"
        case .avalanche: return "avalanche"
        case .base: return "base"
        case .blast: return "blast"
        case .bscChain: return "bsc"
        case .bitcoin: return "bitcoin"
        case .ethereum: return "ethereum"
        case .hyperliquid: return "hyperevm"
        case .optimism: return "optimism"
        case .polygon, .polygonV2: return "polygon"
        case .solana: return "solana"
        case .sui: return "sui"
        default: return nil
        }
    }
}
