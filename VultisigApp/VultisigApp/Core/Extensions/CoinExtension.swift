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
        return chain.coinType
    }

}

extension Array where Element: Coin {

    var totalBalanceInFiatDecimal: Decimal {
        return reduce(Decimal(0), { $0 + $1.balanceInFiatDecimal })
    }

    var totalBalanceInFiatString: String {
        return totalBalanceInFiatDecimal.formatToFiat(includeCurrencySymbol: true)
    }

    var totalDefiBalanceInFiatDecimal: Decimal {
        return reduce(Decimal(0), { $0 + $1.defiBalanceInFiatDecimal })
    }

    var totalDefiBalanceInFiatString: String {
        return totalDefiBalanceInFiatDecimal.formatToFiat(includeCurrencySymbol: true)
    }

    func nativeCoin(chain: Chain) -> Coin? {
        self.first(where: { $0.isNativeToken && $0.chain.name == chain.name })
    }
}
