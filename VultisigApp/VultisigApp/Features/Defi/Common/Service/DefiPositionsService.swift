//
//  DefiPositionsService.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/11/2025.
//

struct DefiPositionsService {
    private let thorchainService = THORChainAPIService()

    func positionCoins(for chain: Chain) -> [CoinMeta] {
        bondCoins(for: chain) + stakeCoins(for: chain)
    }
    
    func bondCoins(for chain: Chain) -> [CoinMeta] {
        switch chain {
        case .thorChain:
            [TokensStore.rune]
        case .mayaChain:
            [TokensStore.cacao]
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
        case .mayaChain:
            [
                TokensStore.cacao
            ]
        default:
            []
        }
    }
    
    func lpCoins(for chain: Chain) async -> [CoinMeta] {
        switch chain {
        case .thorChain:
            let pools = (try? await thorchainService.getPools()) ?? []
            let coins = pools.compactMap { THORChainAssetFactory.createCoin(from: $0.asset) }
            return coins
        case .mayaChain:
            let pools = (try? await MayaChainAPIService().getPoolStats(period: SettingsAPRPeriod.current.rawValue)) ?? []
            let coins = pools.compactMap { THORChainAssetFactory.createCoin(from: $0.asset) }
            return coins
        default:
            return []
        }
    }
}
