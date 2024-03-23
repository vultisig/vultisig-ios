	//
	//  Token.swift
	//  VoltixApp
	//
	//  Created by Amol Kumar on 2024-03-04.
	//

import Foundation
import BigInt

class EthToken: Codable {
	var balance: BigInt? {
		return BigInt(rawBalance)
	}
	var rawBalance: String
	
	var address: String
	var name: String
	var decimals: String
	var symbol: String
	
	var priceRate: Double?
	
	enum CodingKeys: String, CodingKey {
		case rawBalance = "TokenQuantity"
		case address = "TokenAddress"
		case name = "TokenName"
		case decimals = "TokenDivisor"
		case symbol = "TokenSymbol"
	}
	
	var balanceDecimal: Double {
		let tokenBalance = Double(rawBalance) ?? 0.0
		let tokenDecimals = Double(decimals) ?? 0.0
		let balanceInDecimal = (tokenBalance / pow(10, tokenDecimals))
		return balanceInDecimal
	}
	
	var balanceString: String {
		let tokenBalance = Double(rawBalance) ?? 0.0
		let tokenDecimals = Double(decimals) ?? 0.0
		let balanceInDecimal = (tokenBalance / pow(10, tokenDecimals))
		return String(format: "%.\(decimals)f", balanceInDecimal)
	}
	
	func getAmountInUsd(_ amount: Double) -> String {
		let tokenRate = priceRate ?? 0.0
		let balanceInUsd = amount * tokenRate
		return "\(String(format: "%.2f", balanceInUsd))"
	}
	
	func getAmountInTokens(_ usdAmount: Double) -> String {
		let tokenRate = priceRate ?? 0.0
		let tokenAmount = (usdAmount / tokenRate)
		return "\(String(format: "%.\(decimals)f", tokenAmount))"
	}
	
	var balanceInUsd: String {
		let tokenBalance = Double(rawBalance) ?? 0.0
		let tokenRate = priceRate ?? 0.0
		let tokenDecimals = Double(decimals) ?? 0.0
		let balanceInUsd = (tokenBalance / pow(10, tokenDecimals)) * tokenRate
		
		return "US$ \(String(format: "%.2f", balanceInUsd))"
	}
}
