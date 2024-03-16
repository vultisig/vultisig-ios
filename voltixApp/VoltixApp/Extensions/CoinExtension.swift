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
        switch self.chain {
        case .Bitcoin:
            return CoinType.bitcoin
        case Chain.THORChain:
            return CoinType.thorchain
        case Chain.Solana:
            return CoinType.solana
        case Chain.BitcoinCash:
            return CoinType.bitcoinCash
        case Chain.Litecoin:
            return CoinType.litecoin
        case Chain.Dogecoin:
            return CoinType.dogecoin
        case Chain.Ethereum:
            return CoinType.ethereum
        default:
            return nil
        }
    }
}
