//
//  TransactionBroadcastResponse.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 07/03/2024.
//

import Foundation

class CosmosTransactionBroadcastResponse: Codable {
    var txResponse: CosmosTransactionBroadcastTx?
    
    enum CodingKeys: String, CodingKey {
        case txResponse = "tx_response"
    }
}

class CosmosTransactionBroadcastTx: Codable {
    var txhash: String?
    var code: Int?    
    enum CodingKeys: String, CodingKey {
        case txhash, code
    }
}

// MARK: - Transaction Status Response Models
struct CosmosTransactionResponse: Codable {
    let txResponse: CosmosTransactionResponseTx?
    
    enum CodingKeys: String, CodingKey {
        case txResponse = "tx_response"
    }
}

struct CosmosTransactionResponseTx: Codable {
    let txhash: String?
    let code: Int?
    let height: String?
    let gasUsed: String?
    let gasWanted: String?
    let timestamp: String?
    
    enum CodingKeys: String, CodingKey {
        case txhash
        case code
        case height
        case gasUsed = "gas_used"
        case gasWanted = "gas_wanted"
        case timestamp
    }
}
