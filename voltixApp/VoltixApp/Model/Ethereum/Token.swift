import Foundation
import BigInt

class Token: Codable, Equatable, Hashable {
	
	var rawBalance: String
	var address: String
	var name: String
	var decimals: String
	var symbol: String
	var priceRate: Double?
	
	static func == (lhs: Token, rhs: Token) -> Bool {
		lhs.address == rhs.address && lhs.name == rhs.name && lhs.decimals == rhs.decimals && lhs.symbol == rhs.symbol
	}
	
	func hash(into hasher: inout Hasher) {
		hasher.combine(rawBalance)
		hasher.combine(address)
		hasher.combine(name)
		hasher.combine(decimals)
		hasher.combine(symbol)
		hasher.combine(priceRate)
	}
	
	init(rawBalance: String, address: String, name: String, decimals: String, symbol: String, priceRate: Double? = nil) {
		self.rawBalance = rawBalance
		self.address = address
		self.name = name
		self.decimals = decimals
		self.symbol = symbol
		self.priceRate = priceRate
	}
	
	var balance: BigInt? {
		return BigInt(rawBalance)
	}
	
	var balanceDecimal: Double {
		let tokenBalance = Double(rawBalance) ?? 0.0
		let tokenDecimals = Double(decimals) ?? 0.0
		let balanceInDecimal = (tokenBalance / pow(10, tokenDecimals))
		return balanceInDecimal
	}
	
	var balanceString: String {
		let balanceInDecimal = self.balanceDecimal
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
		let balanceInDecimal = self.balanceDecimal
		let tokenRate = priceRate ?? 0.0
		let balanceInUsd = balanceInDecimal * tokenRate
		return "US$ \(String(format: "%.2f", balanceInUsd))"
	}
}
