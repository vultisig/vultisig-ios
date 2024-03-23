//
//  ETHInfo.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-04.
//

import Foundation

class ETHInfo: Codable {
	let price: ETHInfoPrice
	let balance: Double
	let rawBalance: String
	
	init(){
		self.price = ETHInfoPrice()
		self.balance = 0.0
		self.rawBalance = ""
	}
    
    var balanceString: String {
        return "\(String(format: "%.8f", balance))" // Wei is too long
    }
    
    var balanceInUsd: String {
        let ethBalanceInUsd = balance * price.rate
        return "US$ \(String(format: "%.2f", ethBalanceInUsd))"
    }
    
    func getAmountInUsd(_ amount: Double) -> String {
        let ethAmountInUsd = amount * price.rate
        return "\(String(format: "%.2f", ethAmountInUsd))"
    }
    
    func getAmountInEth(_ usdAmount: Double) -> String {
        let ethRate = price.rate
        let amountInEth = usdAmount / ethRate
        return "\(String(format: "%.4f", amountInEth))"
    }
}
