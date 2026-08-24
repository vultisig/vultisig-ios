//
//  TonTransactionStatusResponse.swift
//  VultisigApp
//
//  Created by Claude on 27/01/2025.
//

import Foundation

/// TON Center API v3 /transactionsByMessage response
struct TonTransactionStatusResponse: Codable {
    let transactions: [TonTransaction]?

    struct TonTransaction: Codable {
        let account: String?  // Account address
        let hash: String?  // Transaction hash (base64)
        let lt: String?  // Logical time
        let now: Int?  // Unix timestamp
        let origStatus: String?  // Account status before transaction
        let endStatus: String?  // Account status after transaction
        let totalFees: String?  // Total fees paid
        let data: String?  // Transaction data
        let description: TonDescription?

        struct TonDescription: Codable {
            let aborted: Bool?  // Whether transaction was aborted
            let destroyed: Bool?  // Whether account was destroyed
            let computePhase: ComputePhase?  // TVM compute phase result
            // Where funds actually move: compute can succeed while the action
            // phase fails, moving nothing.
            let action: ActionPhase?

            struct ComputePhase: Codable {
                // 0 / 1 = success, anything else = revert. `nil` for non-contract
                // transfers that have no compute phase.
                let exitCode: Int?

                enum CodingKeys: String, CodingKey {
                    case exitCode = "exit_code"
                }
            }

            struct ActionPhase: Codable {
                let success: Bool?
                let resultCode: Int?

                enum CodingKeys: String, CodingKey {
                    case success
                    case resultCode = "result_code"
                }
            }

            enum CodingKeys: String, CodingKey {
                case aborted
                case destroyed
                case computePhase = "compute_ph"
                case action
            }
        }

        enum CodingKeys: String, CodingKey {
            case account
            case hash
            case lt
            case now
            case origStatus = "orig_status"
            case endStatus = "end_status"
            case totalFees = "total_fees"
            case data
            case description
        }
    }
}
