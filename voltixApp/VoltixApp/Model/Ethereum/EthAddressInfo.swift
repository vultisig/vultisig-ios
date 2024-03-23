//
//  EthAddressInfo.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-04.
//

import SwiftUI

class EthAddressInfo: Codable {
	var address: String
	var tokens: [Token]?
	
	init() {
		self.address = "0x0"
		self.tokens = nil
		
		self.priceRate = 0.0
		self.rawBalance = ""
	}
	
	var priceRate: Double
	
	var rawBalance: String
	
	var balance: Double {
		guard let wei = Double(rawBalance) else {
			return 0.0
		}
		return wei / 1_000_000_000_000_000_000
	}

	var balanceString: String {
		return "\(String(format: "%.8f", balance))" // Wei is too long
	}
	
	var balanceInUsd: String {
		let ethBalanceInUsd = balance * priceRate
		return "US$ \(String(format: "%.2f", ethBalanceInUsd))"
	}
	
	func getAmountInUsd(_ amount: Double) -> String {
		let ethAmountInUsd = amount * priceRate
		return "\(String(format: "%.2f", ethAmountInUsd))"
	}
	
	func getAmountInEth(_ usdAmount: Double) -> String {
		let ethRate = priceRate
		let amountInEth = usdAmount / ethRate
		return "\(String(format: "%.4f", amountInEth))"
	}
	
	func toString() -> String {
		let encoder = JSONEncoder()
		encoder.outputFormatting = .prettyPrinted
		
		do {
			let jsonData = try encoder.encode(self)
			if let jsonString = String(data: jsonData, encoding: .utf8) {
				return jsonString
			}
		} catch {
			print("Error encoding JSON: \(error)")
			return "Error encoding JSON: \(error)"
		}
		return ""
	}
}
