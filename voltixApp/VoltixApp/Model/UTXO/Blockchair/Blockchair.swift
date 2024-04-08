//
//  Blockchair.swift
//  VoltixApp
//
//  Created by Enrique Souza Soares on 17/03/2024.
//

import Foundation

class BlockchairResponse: Codable {
	let data: [String: Blockchair]
}

class Blockchair: Codable {
	var address: BlockchairAddress?
	var transactions: [String]?
	var utxo: [BlockchairUtxo]?
	
	func selectUTXOsForPayment(amountNeeded: Int64) -> [BlockchairUtxo] {
		let txrefs = self.utxo ?? []
		
			// Sort the UTXOs by their value in ascending order
		let sortedTxrefs = txrefs.sorted { $0.value ?? 0 < $1.value  ?? 0 }
		
		var selectedTxrefs: [BlockchairUtxo] = []
		var total = 0
		
			// Iterate through the sorted UTXOs and select enough to cover the amountNeeded
		for txref in sortedTxrefs {
			selectedTxrefs.append(txref)
			total += Int(txref.value  ?? 0)
			if total >= amountNeeded {
				break
			}
		}
		
		return selectedTxrefs
	}
	
	class BlockchairAddress: Codable {
		var type: String?
		var scriptHex: String?
		var balance: Int?

		var balanceInBTC: String {
			formatAsBitcoin(balance ?? 0)
		}
        
        func balanceInFiat(balance: Double, price: Double, includeCurrencySymbol: Bool = true) -> String{
            
            let balanceUtxo = balance / 100_000_000.0
            let balanceFiat = balanceUtxo * price
            
            return balanceFiat.formatToFiat(includeCurrencySymbol: includeCurrencySymbol)
        }
		
		// Helper function to format an amount in satoshis as Bitcoin
        func formatAsBitcoin(_ satoshis: Int) -> String {
			let formatter = NumberFormatter()
			formatter.numberStyle = .decimal
			formatter.maximumFractionDigits = 8 // Bitcoin can have up to 8 decimal places
			formatter.minimumFractionDigits = 1 // Show at least one decimal to indicate it's a decimal value
			formatter.decimalSeparator = "." // Use dot as the decimal separator
			
			// Optionally, set the locale to "en_US_POSIX" for a more standardized formatting
			formatter.locale = Locale(identifier: "en_US_POSIX")
			
			let btcValue = Double(satoshis) / 100_000_000.0 // Convert satoshis to BTC
			return formatter.string(from: NSNumber(value: btcValue)) ?? "0.0"
		}
	}
	
	class BlockchairUtxo: Codable {
		var blockId: Int?
		var transactionHash: String?
		var index: Int?
		var value: Int?
	}
}
