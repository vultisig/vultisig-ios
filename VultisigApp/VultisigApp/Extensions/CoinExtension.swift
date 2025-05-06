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
    
    /// Identifies if this coin is a TCY token
    var isTCY: Bool {
        // TCY is a native token on THORChain
        guard chain == .thorChain else {
            return false
        }
        
        // Check if the ticker is TCY
        return ticker.uppercased() == "TCY"
    }
}

extension Array where Element: Coin {

    var totalBalanceInFiatDecimal: Decimal {
        return reduce(Decimal(0), { $0 + $1.balanceInFiatDecimal })
    }

    var totalBalanceInFiatString: String {
        return totalBalanceInFiatDecimal.formatToFiat(includeCurrencySymbol: true, useAbbreviation: true)
    }
    
    func nativeCoin(chain: Chain) -> Coin? {
        self.first(where: { $0.isNativeToken && $0.chain.name == chain.name })
    }
}
