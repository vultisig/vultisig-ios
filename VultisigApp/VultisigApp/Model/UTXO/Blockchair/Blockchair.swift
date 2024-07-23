//
//  Blockchair.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 17/03/2024.
//

import Foundation

class BlockchairResponse: Codable {
	let data: [String: Blockchair]
}

class Blockchair: Codable {
	var address: BlockchairAddress?
	var utxo: [BlockchairUtxo]?
	
	func selectUTXOsForPayment() -> [BlockchairUtxo] {
		let txrefs = self.utxo ?? []
		return txrefs.sorted { $0.value ?? 0 < $1.value  ?? 0 }
	}
	
	class BlockchairAddress: Codable {
		var scriptHex: String?
		var balance: Int?

		var balanceInBTC: String {
			formatAsBitcoin(balance ?? 0)
		}
        
		
		// Helper function to format an amount in satoshis as Bitcoin
        func formatAsBitcoin(_ satoshis: Int) -> String {
			let btcValue = Decimal(satoshis) / 100_000_000.0 // Convert satoshis to BTC
            return btcValue.formatToDecimal(digits: 8)
		}
	}
	
	class BlockchairUtxo: Codable {
		var transactionHash: String?
		var index: Int?
		var value: Int?
	}
}
