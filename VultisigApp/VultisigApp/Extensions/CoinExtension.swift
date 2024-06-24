//
//  CoinExtension.swift
//  VultisigApp
//
//  Created by Johnny Luo on 15/3/2024.
//

import Foundation
import WalletCore

extension Coin {
    var coinType: CoinType{
        return self.chain.coinType
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
