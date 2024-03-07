//
//  TransactionBroadcastResponse.swift
//  VoltixApp
//
//  Created by Enrique Souza Soares on 07/03/2024.
//

import Foundation

class TransactionBroadcastResponse: Codable {
    let txHash: String
    
    enum CodingKeys: String, CodingKey {
        case txHash = "tx_response"
    }
}
