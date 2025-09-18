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
        
        // DETAILED SELECTION LOGGING
        let totalAvailable = txrefs.reduce(0) { $0 + Int64($1.value ?? 0) }
        let usableUtxos = txrefs.filter { Int64($0.value ?? 0) >= dustThreshold }
        let dustUtxos = txrefs.filter { Int64($0.value ?? 0) < dustThreshold }
        
        print("\n🎯 UTXO SELECTION PROCESS:")
        print("💸 TRANSACTION REQUIREMENTS:")
        print("  Amount needed: \(amountNeeded) satoshis (\(Double(amountNeeded)/100_000_000) coins)")
        print("  Dust threshold: \(dustThreshold) satoshis")
        
        print("\n📦 AVAILABLE UTXOs:")
        print("  Total UTXOs: \(txrefs.count)")
        print("  Total balance: \(totalAvailable) satoshis (\(Double(totalAvailable)/100_000_000) coins)")
        print("  Usable UTXOs: \(usableUtxos.count)")
        print("  Dust UTXOs: \(dustUtxos.count)")
        
        if !usableUtxos.isEmpty {
            let usableBalance = usableUtxos.reduce(0) { $0 + Int64($1.value ?? 0) }
            print("  Usable balance: \(usableBalance) satoshis (\(Double(usableBalance)/100_000_000) coins)")
            
            print("\n🔍 UTXO SELECTION DETAILS:")
            print("  Trying to select from \(usableUtxos.count) usable UTXOs...")
            
            // Show the selection process
            var runningTotal: Int64 = 0
            for (index, utxo) in sortedTxRefs.enumerated() {
                let utxoValue = Int64(utxo.value ?? 0)
                if utxoValue >= dustThreshold {
                    runningTotal += utxoValue
                    let isSelected = selectedTxRefs.contains { $0.transactionHash == utxo.transactionHash && $0.index == utxo.index }
                    let status = isSelected ? "✅ SELECTED" : "⏭️  SKIPPED"
                    print("    [\(index+1)] \(utxoValue) sats (\(Double(utxoValue)/100_000_000) coins) - Running total: \(runningTotal) - \(status)")
                    
                    if runningTotal >= amountNeeded && isSelected {
                        print("    🎉 SUFFICIENT AMOUNT REACHED!")
                        break
                    }
                }
            }
        }
        
        print("\n📊 SELECTION RESULTS:")
        print("  Selected UTXOs: \(selectedTxRefs.count)")
        print("  Selected total: \(total) satoshis (\(Double(total)/100_000_000) coins)")
        print("  Required amount: \(amountNeeded) satoshis (\(Double(amountNeeded)/100_000_000) coins)")
        print("  Difference: \(total - amountNeeded) satoshis")
        print("  Success: \(total >= amountNeeded ? "✅ YES" : "❌ NO")")
        
        if total < amountNeeded {
            print("\n⚠️  SELECTION FAILED ANALYSIS:")
            if usableUtxos.isEmpty {
                print("  ❌ No usable UTXOs (all are dust)")
            } else {
                let usableBalance = usableUtxos.reduce(0) { $0 + Int64($1.value ?? 0) }
                if usableBalance < amountNeeded {
                    print("  ❌ Insufficient usable balance: \(usableBalance) < \(amountNeeded)")
                } else {
                    print("  ❌ Selection algorithm failed despite having enough balance")
                    print("  💡 This might be a fragmentation issue")
                }
            }
        }
        
        print("🎯 END SELECTION PROCESS\n")
        
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
