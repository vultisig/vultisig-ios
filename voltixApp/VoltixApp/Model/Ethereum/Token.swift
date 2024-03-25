import Foundation
import BigInt

class Token: Codable, Equatable, Hashable {
	
	var address: String
	var name: String
	var decimals: String
	var symbol: String
	
	static func == (lhs: Token, rhs: Token) -> Bool {
		lhs.address == rhs.address && lhs.name == rhs.name && lhs.decimals == rhs.decimals && lhs.symbol == rhs.symbol
	}
	
	func hash(into hasher: inout Hasher) {
		hasher.combine(address)
		hasher.combine(name)
		hasher.combine(decimals)
		hasher.combine(symbol)
	}
	
	init(address: String, name: String, decimals: String, symbol: String) {
		self.address = address
		self.name = name
		self.decimals = decimals
		self.symbol = symbol
	}
}
