//
//  UTXOTransactionStatusResponse.swift
//  VultisigApp
//
//  Created by Claude on 23/01/2025.
//

import Foundation

struct UTXOTransactionStatusResponse: Codable {
    let status: UTXOStatus?

    struct UTXOStatus: Codable {
        let confirmed: Bool
        let blockHeight: Int?

        enum CodingKeys: String, CodingKey {
            case confirmed
            case blockHeight = "block_height"
        }
    }
}
