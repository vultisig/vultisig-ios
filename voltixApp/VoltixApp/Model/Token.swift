//
//  Token.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-04.
//

import Foundation

class Token: Codable {
    let tokenInfo: TokenInfo
    let balance: Int // If always integer in JSON
    let rawBalance: String
    
    var balanceDecimal: Double {
        let tokenBalance = Double(rawBalance) ?? 0.0
        let tokenDecimals = Double(tokenInfo.decimals) ?? 0.0
        let balanceInDecimal = (tokenBalance / pow(10, tokenDecimals))
        return balanceInDecimal
    }
    
    var balanceString: String {
        let tokenBalance = Double(rawBalance) ?? 0.0
        let tokenDecimals = Double(tokenInfo.decimals) ?? 0.0
        let balanceInDecimal = (tokenBalance / pow(10, tokenDecimals))
        return String(format: "%.\(tokenInfo.decimals)f", balanceInDecimal)
    }
    
    func getAmountInUsd(_ amount: Double) -> String {
        let tokenRate = tokenInfo.price.rate
        // let tokenDecimals = Double(tokenInfo.decimals) ?? 0.0
        // let balanceInUsd = (amount / pow(10, tokenDecimals)) * tokenRate
        let balanceInUsd = amount * tokenRate
        return "\(String(format: "%.2f", balanceInUsd))"
    }
    
    func getAmountInTokens(_ usdAmount: Double) -> String {
        let tokenRate = tokenInfo.price.rate
        // let tokenDecimals = Double(tokenInfo.decimals) ?? 0.0
        let tokenAmount = (usdAmount / tokenRate) // * pow(10, tokenDecimals)
        return "\(String(format: "%.\(tokenInfo.decimals)f", tokenAmount))"
    }
    
    var balanceInUsd: String {
        let tokenBalance = Double(rawBalance) ?? 0.0
        let tokenRate = tokenInfo.price.rate
        let tokenDecimals = Double(tokenInfo.decimals) ?? 0.0
        let balanceInUsd = (tokenBalance / pow(10, tokenDecimals)) * tokenRate
        
        return "US$ \(String(format: "%.2f", balanceInUsd))"
    }
}
