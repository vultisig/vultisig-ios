//
//  SolanaTransactionStatusResponse.swift
//  VultisigApp
//
//  Created by Claude on 23/01/2025.
//

import Foundation

struct SolanaTransactionStatusResponse: Decodable {
    let result: SolanaResult?

    struct SolanaResult: Decodable {
        let value: [SolanaStatusValue?]
    }

    struct SolanaStatusValue: Decodable {
        let slot: Int?
        let confirmationStatus: String?
        let err: SolanaRPCJSONValue?

        enum CodingKeys: String, CodingKey {
            case slot
            case confirmationStatus
            case err
        }
    }
}
