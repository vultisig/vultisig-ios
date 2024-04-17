//
//  THORBalanceExtension.swift
//  VoltixApp
//
//  Created by Johnny Luo on 22/3/2024.
//

import Foundation

extension [CosmosBalance] {
    
    func coinBalanceInFiat(price: Double?, includeCurrencySymbol: Bool = true, coin: Coin) -> String?{
        guard let price = price,
              let coinBalanceString = coinBalance(ticker: coin.ticker),
              let coinAmount = Decimal(string: coinBalanceString) else { return nil }
        let decimals = Int(coin.decimals)
        // decimals should have been specified in tokenstore when we define the coin , otherwise this should return nil
        guard let decimals else {
            return nil
        }
        let balanceCoin = coinAmount / pow(10,decimals)
        let balanceFiat = balanceCoin * Decimal(price)
        return balanceFiat.formatToFiat()
    }
    
    func coinBalance(ticker: String) -> String? {
        for balance in self {
            if balance.denom.lowercased() == ticker.lowercased() {
                return balance.amount
            }
        }
        return nil
    }
    
    func formattedCoinBalance(coin: Coin) -> String? {
        for balance in self {
            if balance.denom.lowercased() == coin.ticker.lowercased() {
                guard let coinAmount = Decimal(string: balance.amount) else {
                    return NSLocalizedString("invalidBalance", comment: "Invalid Balance")
                }
                guard let decimals = Int(coin.decimals) else {
                    return NSLocalizedString("invalidBalance", comment: "Invalid Balance")
                }
                let balanceCoin = coinAmount / pow(10,decimals)
                // Let's keep 4 decimals for coin balance , more than 4 is not meaningful
                return balanceCoin.formatToDecimal(digits: 4)
            }
        }
        
        return NSLocalizedString("balanceNotAvailable", comment: "Balance not available")
    }
}
