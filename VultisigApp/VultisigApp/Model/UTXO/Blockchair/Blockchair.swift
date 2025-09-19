//
//  Blockchair.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 17/03/2024.
//

import Foundation
import WalletCore

class BlockchairResponse: Codable {
	let data: [String: Blockchair]
}

class Blockchair: Codable {
	var address: BlockchairAddress?
	var utxo: [BlockchairUtxo]?
	
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
