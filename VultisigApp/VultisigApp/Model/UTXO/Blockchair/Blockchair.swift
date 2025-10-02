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
	
    func selectUTXOsForPayment(amountNeeded: Int64, coinType: CoinType) -> [BlockchairUtxo] {
        let txrefs = self.utxo ?? []
        
        // Sort UTXOs: smallest first for better UTXO management (avoids fragmentation)
        let sortedTxRefs = txrefs.sorted { $0.value ?? 0 < $1.value ?? 0 }
        var selectedTxRefs: [BlockchairUtxo] = []
        var total: Int64 = 0
        let dustThreshold = Int64(coinType.getFixedDustThreshold())
        
        // First pass: try to select UTXOs efficiently
        for txref in sortedTxRefs {
            let utxoValue = Int64(txref.value ?? 0)
            
            // Skip dust UTXOs (too small to be economical)
            if utxoValue < dustThreshold {
                continue
            }
            
            selectedTxRefs.append(txref)
            total += utxoValue
            
            // Stop when we have enough
            if total >= amountNeeded {
                break
            }
        }
        
        
        return selectedTxRefs
    }
	
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
