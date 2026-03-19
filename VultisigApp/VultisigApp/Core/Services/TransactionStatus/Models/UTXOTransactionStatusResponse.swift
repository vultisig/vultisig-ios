//
//  UTXOTransactionStatusResponse.swift
//  VultisigApp
//
//  Created by Claude on 23/01/2025.
//

import Foundation

/// Response format for UTXO transaction status
/// Supports Blockchair format for all UTXO chains
struct UTXOTransactionStatusResponse: Codable {
    // Blockchair format
    // Note: Blockchair returns [] when no results, or {txHash: {...}} when found
    let data: [String: BlockchairTransactionData]?

    struct BlockchairTransactionData: Codable {
        let transaction: BlockchairTransaction

        struct BlockchairTransaction: Codable {
            let blockId: Int
            let hash: String?

            enum CodingKeys: String, CodingKey {
                case blockId = "block_id"
                case hash
            }

            /// Returns true if transaction is confirmed (in a block)
            /// block_id == -1 means transaction is in mempool (unconfirmed)
            var isConfirmed: Bool {
                blockId != -1
            }

            /// Returns block number if confirmed, nil if pending
            var blockNumber: Int? {
                isConfirmed ? blockId : nil
            }
        }
    }
}
