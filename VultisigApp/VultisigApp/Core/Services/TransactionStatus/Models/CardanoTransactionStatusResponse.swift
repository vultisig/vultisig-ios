//
//  CardanoTransactionStatusResponse.swift
//  VultisigApp
//
//  Created by Claude on 27/01/2025.
//

import Foundation

/// Koios API /tx_status response
/// Returns array of transaction status objects
struct CardanoTransactionStatusResponse: Codable {
    // Response is a direct array, not wrapped in a "data" field
    let txStatuses: [CardanoTxStatus]

    struct CardanoTxStatus: Codable {
        let tx_hash: String
        let num_confirmations: Int?  // nil if transaction not found or pending
    }

    // Custom decoding to handle array response
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        txStatuses = try container.decode([CardanoTxStatus].self)
    }

    // Custom encoding
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(txStatuses)
    }
}
