//
//  TronTransactionStatusResponse.swift
//  VultisigApp
//
//  Created by Claude on 27/01/2025.
//

import Foundation

struct TronTransactionStatusResponse: Codable {
    let id: String?
    let blockNumber: Int?
    let blockTimeStamp: Int64?
    let fee: Int?
    let receipt: TronReceipt?
    let result: String?  // Top-level result field (present on failure)
    let resMessage: String?  // Error message (present on failure)

    struct TronReceipt: Codable {
        // Present on both success and failure per Tron protocol.
        // Values: "SUCCESS" (committed), "FAILED", "REVERT", "OUT_OF_ENERGY",
        // "OUT_OF_TIME", "BANDWIDTH_ERROR", "ACCOUNT_FREEZED" (failure modes).
        // Empty string also possible when a contract executes without explicit code.
        // See sdk#545 + https://developers.tron.network/reference/gettransactioninfobyid
        let result: String?
        let net_fee: Int?
        let energy_fee: Int?
        let energy_usage_total: Int64?
    }

    enum CodingKeys: String, CodingKey {
        case id
        case blockNumber
        case blockTimeStamp
        case fee
        case receipt
        case result
        case resMessage
    }
}
