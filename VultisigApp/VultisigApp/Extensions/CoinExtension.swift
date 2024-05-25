//
//  CoinExtension.swift
//  VultisigApp
//
//  Created by Johnny Luo on 15/3/2024.
//

import Foundation
import WalletCore

extension Coin {
    
    var coinType: CoinType {
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
        case .kujira:
            return CoinType.kujira
        case .dash:
            return CoinType.dash
        case .mayaChain:
            return CoinType.thorchain
        case .arbitrum:
            return CoinType.arbitrum
        case .polygon:
            return CoinType.polygon
        case .base:
            return CoinType.base
        case .optimism:
            return CoinType.optimism
        case .blast:
            return CoinType.blast
        case .cronosChain:
            return CoinType.cronosChain
        case .sui:
            return CoinType.sui
        case .polkadot:
            return CoinType.polkadot
        }
    }
}

extension Array where Element: Coin {

    var totalBalanceInFiatDecimal: Decimal {
        return reduce(Decimal(0), { $0 + $1.balanceInFiatDecimal })
    }

    var totalBalanceDecimal: Decimal {
        return reduce(Decimal(0), { $0 + $1.balanceDecimal })
    }

    var totalBalanceInFiatString: String {
        return totalBalanceInFiatDecimal.formatToFiat(includeCurrencySymbol: true)
    }
}
