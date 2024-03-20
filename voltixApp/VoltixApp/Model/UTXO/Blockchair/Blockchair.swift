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
		var balanceUsd: Double?
		var received: Int?
		var receivedUsd: Double?
		var spent: Int?
		var spentUsd: Double?
		var outputCount: Int?
		var unspentOutputCount: Int?
		var firstSeenReceiving: String?
		var lastSeenReceiving: String?
		var firstSeenSpending: String?
		var lastSeenSpending: String?
		var scripthashType: String?
		var transactionCount: Int?
		
		
		var balanceInBTC: String {
			formatAsBitcoin(balance ?? 0)
		}
		
		var balanceInUSD: String {
			let formatter = NumberFormatter()
			formatter.numberStyle = .currency
			formatter.locale = Locale.current
			formatter.currencyCode = "USD"
			return formatter.string(from: NSNumber(value: balanceUsd ?? 0.0)) ?? "0.0"
		}
		
		var balanceInDecimalUSD: String {
			let formatter = NumberFormatter()
			formatter.numberStyle = .decimal
			formatter.decimalSeparator = "."
			formatter.locale = Locale.current
			formatter.minimumFractionDigits = 2
			formatter.maximumFractionDigits = 2

			return formatter.string(from: NSNumber(value: balanceUsd ?? 0.0)) ?? "0.00"
		}

		// Helper function to format an amount in satoshis as Bitcoin
		private func formatAsBitcoin(_ satoshis: Int) -> String {
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
