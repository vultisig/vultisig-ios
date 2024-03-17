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
	
	class BlockchairAddress: Codable {
		var type: String?
		var scriptHex: String?
		var balance: Int?
		var balanceUSD: Double?
		var received: Int?
		var receivedUSD: Double?
		var spent: Int?
		var spentUSD: Double?
		var outputCount: Int?
		var unspentOutputCount: Int?
		var firstSeenReceiving: String?
		var lastSeenReceiving: String?
		var firstSeenSpending: String?
		var lastSeenSpending: String?
		var scripthashType: String?
		var transactionCount: Int?
	}
	
	class BlockchairUtxo: Codable {
		var blockId: Int?
		var transactionHash: String?
		var index: Int?
		var value: Int?
	}
}
