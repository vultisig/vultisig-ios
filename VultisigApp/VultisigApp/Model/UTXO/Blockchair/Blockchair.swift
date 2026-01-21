//
//  Blockchair.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 17/03/2024.
//

import Foundation
import WalletCore

struct BlockchairResponse: Codable {
	let data: [String: Blockchair]
}

struct Blockchair: Codable {
	let address: BlockchairAddress?
	let utxo: [BlockchairUtxo]?
	
    struct BlockchairAddress: Codable {
		let scriptHex: String?
		let balance: Int?

		var balanceInBTC: String {
			formatAsBitcoin(balance ?? 0)
		}
		// Helper function to format an amount in satoshis as Bitcoin
        func formatAsBitcoin(_ satoshis: Int) -> String {
			let btcValue = Decimal(satoshis) / 100_000_000.0 // Convert satoshis to BTC
            return btcValue.formatToDecimal(digits: 8)
		}
	}
	
    struct BlockchairUtxo: Codable {
        let transactionHash: String?
        let index: Int?
        let value: Int?
	}
}
