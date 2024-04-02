//
//  TransactionBroadcastResponse.swift
//  VoltixApp
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
    var height: String?
    var txhash: String?
    var codespace: String?
    var code: Int?
    var data: String?
    var rawLog: String?
    var gasWanted: String?
    var gasUsed: String?
    
    enum CodingKeys: String, CodingKey {
        case height, txhash, codespace, code, data, rawLog = "raw_log", gasWanted = "gas_wanted", gasUsed = "gas_used"
    }
}
