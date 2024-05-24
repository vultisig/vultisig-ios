//
//  BalanceCachedData.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 23/05/24.
//

import Foundation

class BalanceCachedData {
    let rawBalance: String
    let priceRate: Double
    let coinBalance: String
    let balanceFiat: String
    let balanceInFiatDecimal: Decimal
    
    init(rawBalance: String, priceRate: Double, coinBalance: String, balanceFiat: String, balanceInFiatDecimal: Decimal) {
        self.rawBalance = rawBalance
        self.priceRate = priceRate
        self.coinBalance = coinBalance
        self.balanceFiat = balanceFiat
        self.balanceInFiatDecimal = balanceInFiatDecimal
    }
}
