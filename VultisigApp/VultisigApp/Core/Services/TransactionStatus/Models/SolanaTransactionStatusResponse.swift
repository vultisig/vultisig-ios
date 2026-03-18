//
//  SolanaTransactionStatusResponse.swift
//  VultisigApp
//
//  Created by Claude on 23/01/2025.
//

import Foundation

struct SolanaTransactionStatusResponse: Codable {
    let result: SolanaResult?

    struct SolanaResult: Codable {
        let value: [SolanaStatusValue?]
    }

    struct SolanaStatusValue: Codable {
        let slot: Int?
        let confirmationStatus: String?
        let err: SolanaError?

        enum CodingKeys: String, CodingKey {
            case slot
            case confirmationStatus
            case err
        }
    }

    struct SolanaError: Codable {
        // Can be various types, just capture as dictionary
    }
}
