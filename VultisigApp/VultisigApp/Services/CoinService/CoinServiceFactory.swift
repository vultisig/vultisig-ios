//
//  CoinServiceFactory.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 05/07/24.
//

import Foundation

@MainActor
class CoinServiceFactory {
    
    static func getService(for coin: Coin) -> CoinService {
        switch coin.chain.chainType {
        case .EVM:
            return EvmCoinService()
        case .UTXO:
            return UtxoCoinService()
        case .Cosmos:
            return CosmosCoinService()
        default:
            return CoinService()
        }
    }
    
    static func getService(for coin: CoinMeta) -> CoinService {
        switch coin.chain.chainType {
        case .EVM:
            return EvmCoinService()
        case .UTXO:
            return UtxoCoinService()
        case .Cosmos:
            return CosmosCoinService()
        default:
            return CoinService()
        }
    }
    
}
