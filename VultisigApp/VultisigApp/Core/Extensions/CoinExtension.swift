//
//  CoinExtension.swift
//  VultisigApp
//
//  Created by Johnny Luo on 15/3/2024.
//

import BigInt
import Foundation
import WalletCore

extension Coin {

    var coinType: CoinType {
        return chain.coinType
    }

    static let defiOnlyTickers: Set<String> = ["STCY", "YBRUNE"]

    var isDefiOnly: Bool {
        Coin.defiOnlyTickers.contains(ticker.uppercased())
    }

    /// The balance in base units, read exactly.
    ///
    /// `rawBalance` is a base-unit integer string, and this is the reading of it
    /// that the send affordability guards share, so none of them can drift onto
    /// a value that is merely close to the real one. A value that isn't a plain
    /// integer still goes through the shared parse rather than collapsing to a
    /// zero balance.
    ///
    /// Not yet universal: guards outside Send still weigh amounts against
    /// `balanceDecimal`, which divides through the same `Double`-backed parser
    /// this exists to avoid.
    var balanceRaw: BigInt {
        rawBalance.toBigInt(decimals: decimals)
    }
}

extension Array where Element: Coin {

    var totalBalanceInFiatDecimal: Decimal {
        return reduce(Decimal(0)) { $0 + ($1.isDefiOnly ? 0 : $1.balanceInFiatDecimal) }
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
