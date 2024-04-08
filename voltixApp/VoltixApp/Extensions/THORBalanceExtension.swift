//
//  THORBalanceExtension.swift
//  VoltixApp
//
//  Created by Johnny Luo on 22/3/2024.
//

import Foundation

extension [CosmosBalance] {
    func runeBalanceInFiat(price: Double?, includeCurrencySymbol: Bool = true) -> String?{
        guard let price = price,
              let runeBalanceString = runeBalance(),
              let runeAmount = Double(runeBalanceString) else { return nil }
        
        let balanceRune = runeAmount / 100_000_000.0
        let balanceFiat = balanceRune * price
        
        return balanceFiat.formatToFiat()
    }
    
    func runeBalance() -> String? {
        for balance in self {
            if balance.denom.lowercased() == Chain.thorChain.ticker.lowercased() {
                return balance.amount
            }
        }
        return nil
    }
    
    func formattedRuneBalance() -> String? {
        for balance in self {
            if balance.denom.lowercased() == Chain.thorChain.ticker.lowercased() {
                guard let runeAmount = Double(balance.amount) else { return "Invalid balance" }
                let balanceRune = runeAmount / 100_000_000.0
                
                let formatter = NumberFormatter()
                formatter.numberStyle = .decimal
                formatter.maximumFractionDigits = 8
                formatter.minimumFractionDigits = 0
                formatter.groupingSeparator = ""
                formatter.decimalSeparator = "."
                return formatter.string(from: NSNumber(value: balanceRune))
            }
        }
        
        return "Balance not available"
    }
    func atomBalance() -> String? {
        for balance in self {
            if balance.denom.lowercased() == Chain.gaiaChain.ticker.lowercased() {
                return balance.amount
            }
        }
        return nil
    }
    
    func atomBalanceInFiat(price: Double?, includeCurrencySymbol: Bool = true) -> String?{
        guard let price = price,
              let runeBalanceString = atomBalance(),
              let runeAmount = Double(runeBalanceString) else { return nil }
        
        let balanceAtom = runeAmount / 1000_000.0
        let balanceFiat = balanceAtom * price
        
        return balanceFiat.formatToFiat()
    }
    
    func formattedAtomBalance() -> String? {
        for balance in self {
            if balance.denom.lowercased() == Chain.gaiaChain.ticker.lowercased() {
                guard let atomAmount = Double(balance.amount) else { return "Invalid balance" }
                let balanceAtom = atomAmount / 1_000_000.0
                
                let formatter = NumberFormatter()
                formatter.numberStyle = .decimal
                formatter.maximumFractionDigits = 6
                formatter.minimumFractionDigits = 0
                formatter.groupingSeparator = ""
                formatter.decimalSeparator = "."
                return formatter.string(from: NSNumber(value: balanceAtom))
            }
        }
        
        return "Balance not available"
    }
    
}
