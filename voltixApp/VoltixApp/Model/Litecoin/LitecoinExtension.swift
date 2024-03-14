//
//  Litecoin.swift
//  VoltixApp
//
//  Created by Enrique Souza Soares on 13/03/2024.
//

import Foundation

extension LitecoinUnspentOutputsService {
	class LitecoinTransactionRef: Codable {
		let txid: String
		let vout: Int
		let status: Status
		let value: Int
		
		class Status: Codable {
			let confirmed: Bool
			let blockHeight: Int
			let blockHash: String
			let blockTime: Int
			
			enum CodingKeys: String, CodingKey {
				case confirmed
				case blockHeight = "block_height"
				case blockHash = "block_hash"
				case blockTime = "block_time"
			}
		}
	}
	
	class LitecoinTransaction: Codable {
		let utxos: [LitecoinTransactionRef]
		
		init(utxos: [LitecoinTransactionRef]) {
			self.utxos = utxos
		}
		
		enum CodingKeys: String, CodingKey {
			case utxos
		}
		
		var balance: Int {
			utxos.reduce(0) { $0 + $1.value }
		}
		
		var balanceDecimal: Double {
			Double(balance) / 100_000_000.0
		}
		
		var balanceInLTC: String {
			formatAsLitecoin(balance)
		}
		
		private func formatAsLitecoin(_ satoshis: Int) -> String {
			let formatter = NumberFormatter()
			formatter.numberStyle = .decimal
			formatter.maximumFractionDigits = 8
			formatter.minimumFractionDigits = 1
			formatter.decimalSeparator = "."
			formatter.locale = Locale(identifier: "en_US_POSIX")
			
			let ltcValue = Double(satoshis) / 100_000_000.0 // Convert satoshis to LTC
			return formatter.string(from: NSNumber(value: ltcValue)) ?? "0.0"
		}
		
		func balanceInUSD(usdPrice: Double?) -> String? {
			guard let usdPrice = usdPrice else { return nil }
			let balanceLTC = balanceDecimal // Balance in LTC
			let balanceUSD = balanceLTC * usdPrice // Convert LTC to USD
			
			let formatter = NumberFormatter()
			formatter.numberStyle = .currency
			formatter.locale = Locale.current
			formatter.currencyCode = "USD"
			
			return formatter.string(from: NSNumber(value: balanceUSD))
		}
		
		func selectUTXOsForPayment(amountNeeded: Int64) -> [LitecoinTransactionRef] {
			let sortedUtxos = utxos.sorted { $0.value < $1.value }
			
			var selectedUtxos: [LitecoinTransactionRef] = []
			var total = 0
			
			for utxo in sortedUtxos {
				selectedUtxos.append(utxo)
				total += utxo.value
				if total >= amountNeeded {
					break
				}
			}
			
			return selectedUtxos
		}
	}
}

