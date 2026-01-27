//
//  PolkadotTransactionStatusResponse.swift
//  VultisigApp
//
//  Created by Claude on 27/01/2025.
//

import Foundation

/// Subscan API response for /api/scan/extrinsic
struct PolkadotTransactionStatusResponse: Codable {
    let code: Int  // 0 = success, non-zero = error
    let message: String  // "Success" or error message
    let data: PolkadotExtrinsicData?

    struct PolkadotExtrinsicData: Codable {
        let extrinsic_hash: String?
        let success: Bool  // true = successful, false = failed
        let block_num: Int?  // Block number
        let block_timestamp: Int?  // Unix timestamp
        let call_module: String?  // e.g., "balances"
        let call_module_function: String?  // e.g., "transfer"
        let account_id: String?  // Sender address
        let signature: String?
        let nonce: Int?
        let finalized: Bool?  // Whether the transaction is finalized
        let error: PolkadotExtrinsicError?  // Present when success = false

        // Additional fields that might be in response
        let extrinsic_index: String?
        let fee: String?
    }

    struct PolkadotExtrinsicError: Codable {
        let module: String?
        let name: String?
        let doc: [String]?  // Error description
    }
}
