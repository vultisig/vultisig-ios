//
//  TransactionRef.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-04.
//

import Foundation

class BitcoinTransactionRef: Codable, Identifiable {
    var id: String {
        txHash ?? "N/A" // Use txHash as the identifier, or a fallback if missing
    }
    let txHash: String?
    let blockHeight: Int?
    let txInputN: Int?
    let txOutputN: Int?
    let value: Int64?
    let refBalance: Int?
    let spent: Bool?
    let confirmations: Int?
    let confirmed: String?
    let doubleSpend: Bool?
    
    enum CodingKeys: String, CodingKey {
        case txHash = "tx_hash"
        case blockHeight = "block_height"
        case txInputN = "tx_input_n"
        case txOutputN = "tx_output_n"
        case value
        case refBalance = "ref_balance"
        case spent
        case confirmations
        case confirmed
        case doubleSpend = "double_spend"
    }
}
