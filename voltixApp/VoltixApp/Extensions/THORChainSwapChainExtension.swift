//
//  THORChainSwapChainExtension.swift
//  VoltixApp
//

import Foundation
import WalletCore

extension THORChainSwapChain {
    func getCoinType() -> CoinType? {
        switch self {
        case .atom:
            return CoinType.cosmos
        case .thor:
            return CoinType.thorchain
        case .btc:
            return CoinType.bitcoin
        case .eth:
            return CoinType.ethereum
        case .bnb:
            return CoinType.binance
        case .doge:
            return CoinType.dogecoin
        case .bch:
            return CoinType.bitcoinCash
        case .ltc:
            return CoinType.litecoin
        case .avax:
            return CoinType.avalancheCChain
        case .bsc:
            return CoinType.smartChain
        default:
            return nil
        }
    }
}
