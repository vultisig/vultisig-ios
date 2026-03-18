//
//  CosmosTransactionStatusResponse.swift
//  VultisigApp
//
//  Created by Claude on 23/01/2025.
//

import Foundation

struct CosmosTransactionStatusResponse: Codable {
    let txResponse: CosmosTxResponse?

    struct CosmosTxResponse: Codable {
        let code: Int
        let height: String?
        let rawLog: String?

        enum CodingKeys: String, CodingKey {
            case code
            case height
            case rawLog = "raw_log"
        }
    }

    enum CodingKeys: String, CodingKey {
        case txResponse = "tx_response"
    }
}
