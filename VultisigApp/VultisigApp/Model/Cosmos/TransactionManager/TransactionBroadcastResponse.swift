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
