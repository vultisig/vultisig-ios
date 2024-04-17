//
//  CoinExtension.swift
//  VoltixApp
//
//  Created by Johnny Luo on 15/3/2024.
//

import Foundation
import WalletCore

extension Coin {

    func getCoinType() -> CoinType? {
        switch chain {
        case .bitcoin:
            return CoinType.bitcoin
        case .thorChain:
            return CoinType.thorchain
        case .solana:
            return CoinType.solana
        case .bitcoinCash:
            return CoinType.bitcoinCash
        case .litecoin:
            return CoinType.litecoin
        case .dogecoin:
            return CoinType.dogecoin
        case .ethereum:
            return CoinType.ethereum
        case .bscChain:
            return CoinType.smartChain
        case .avalanche:
            return CoinType.avalancheCChain
        case .gaiaChain:
            return CoinType.cosmos
        case .dash:
            return CoinType.dash
        case .mayaChain:
            return CoinType.thorchain
        }
    }
}
