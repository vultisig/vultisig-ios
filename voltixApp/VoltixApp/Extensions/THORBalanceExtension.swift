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
              let runeAmount = Decimal(string: runeBalanceString) else { return nil }
        
        let balanceRune = runeAmount / 100_000_000.0
        let balanceFiat = balanceRune * Decimal(price)
        
        return balanceFiat.formatToFiat()
    }
    
    func cacaoBalanceInFiat(price: Double?, includeCurrencySymbol: Bool = true) -> String?{
        guard let price = price,
              let cacaoBalanceString = cacaoBalance(),
              let cacaoAmount = Decimal(string: cacaoBalanceString) else { return nil }
        
        let balanceCacao = cacaoAmount / 100_000_00000.0
        let balanceFiat = balanceCacao * Decimal(price)
        
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
    
    func cacaoBalance() -> String? {
        for balance in self {
            if balance.denom.lowercased() == Chain.mayaChain.ticker.lowercased() {
                return balance.amount
            }
        }
        return nil
    }
    
    func formattedRuneBalance() -> String? {
        for balance in self {
            if balance.denom.lowercased() == Chain.thorChain.ticker.lowercased() {
                guard let runeAmount = Decimal(string: balance.amount) else { return "Invalid balance" }
                let balanceRune = runeAmount / 100_000_000.0
                return balanceRune.formatToDecimal(digits: 8)
            }
        }
        
        return "Balance not available"
    }
    func formattedCacaoBalance() -> String? {
        for balance in self {
            if balance.denom.lowercased() == Chain.mayaChain.ticker.lowercased() {
                guard let runeAmount = Decimal(string: balance.amount) else { return "Invalid balance" }
                let balanceCacao = runeAmount / 100_000_00000.0
                return balanceCacao.formatToDecimal(digits: 10)
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
              let atomBalanceString = atomBalance(),
              let atomAmount = Decimal(string: atomBalanceString) else { return nil }
        
        let balanceAtom = atomAmount / 1000_000.0
        let balanceFiat = balanceAtom * Decimal(price)
        return balanceFiat.formatToFiat()
    }
    
    func formattedAtomBalance() -> String? {
        for balance in self {
            if balance.denom.lowercased() == Chain.gaiaChain.ticker.lowercased() {
                guard let atomAmount = Decimal(string: balance.amount) else { return "Invalid balance" }
                let balanceAtom = atomAmount / 1_000_000.0
                return balanceAtom.formatToDecimal(digits: 6)
            }
        }
        
        return "Balance not available"
    }
    
}
