//
//  THORBalanceExtension.swift
//  VoltixApp
//
//  Created by Johnny Luo on 22/3/2024.
//

import Foundation

extension [CosmosBalance] {
    func runeBalanceInUSD(usdPrice: Double?, includeCurrencySymbol: Bool = true) -> String?{
        guard let usdPrice = usdPrice,
              let runeBalanceString = runeBalance(),
              let runeAmount = Double(runeBalanceString) else { return nil }
        
        let balanceRune = runeAmount / 100_000_000.0
        let balanceUSD = balanceRune * usdPrice
        
        let formatter = NumberFormatter()
        
        if includeCurrencySymbol {
            formatter.numberStyle = .currency
            formatter.currencyCode = "USD"
        } else {
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            formatter.minimumFractionDigits = 2
            formatter.decimalSeparator = "."
            formatter.groupingSeparator = ""
        }
        
        return formatter.string(from: NSNumber(value: balanceUSD))
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
    
    func atomBalanceInUSD(usdPrice: Double?, includeCurrencySymbol: Bool = true) -> String?{
        guard let usdPrice = usdPrice,
              let runeBalanceString = atomBalance(),
              let runeAmount = Double(runeBalanceString) else { return nil }
        
        let balanceAtom = runeAmount / 1000_000.0
        let balanceUSD = balanceAtom * usdPrice
        
        let formatter = NumberFormatter()
        
        if includeCurrencySymbol {
            formatter.numberStyle = .currency
            formatter.currencyCode = "USD"
        } else {
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            formatter.minimumFractionDigits = 2
            formatter.decimalSeparator = "."
            formatter.groupingSeparator = ""
        }
        
        return formatter.string(from: NSNumber(value: balanceUSD))
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
