//
//  DefiPositionsService.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/11/2025.
//

struct DefiPositionsService {
    func positionCoins(for chain: Chain) -> [CoinMeta] {
        bondCoins(for: chain) + stakeCoins(for: chain)
    }
    
    func bondCoins(for chain: Chain) -> [CoinMeta] {
        switch chain {
        case .thorChain:
            [TokensStore.rune]
        default:
            []
        }
    }
    
    func stakeCoins(for chain: Chain) -> [CoinMeta] {
        switch chain {
        case .thorChain:
            [
                TokensStore.tcy,
                TokensStore.ruji,
                TokensStore.yrune,
                TokensStore.ytcy
            ]
        default:
            []
        }
    }
}
