//
//  THORChainTransactionStatusResponse.swift
//  VultisigApp
//
//  Created by Claude on 27/01/2025.
//

import Foundation

// Midgard Actions API Response
struct THORChainActionsResponse: Codable {
    let actions: [MidgardAction]
    let count: String
}

struct MidgardAction: Codable {
    let pools: [String]
    let type: String
    let status: String  // "success", "pending", "refund"
    let `in`: [MidgardTransaction]
    let out: [MidgardTransaction]
    let date: String
    let height: String
    let metadata: MidgardActionMetadata?
}

struct MidgardTransaction: Codable {
    let txID: String
    let address: String?
    let coins: [MidgardCoin]?

    enum CodingKeys: String, CodingKey {
        case txID
        case address
        case coins
    }
}

struct MidgardCoin: Codable {
    let asset: String
    let amount: String
}

struct MidgardActionMetadata: Codable {
    let refund: RefundMetadata?
    let failed: FailedMetadata?
}

struct RefundMetadata: Codable {
    let reason: String?
    let code: Int?
    let memo: String?
    let networkFees: [MidgardCoin]?
}

struct FailedMetadata: Codable {
    let reason: String?
    let code: Int?
    let memo: String?
}
