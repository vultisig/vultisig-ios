//
//  LifiQuoteResponse.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 17.01.2025.
//

import Foundation

enum LifiQuoteResponse: Codable {
    struct EvmQuoteResponse: Codable {
        struct TransactionRequest: Codable {
            let data: String
            let to: String
            let value: String
            let from: String
            let chainId: Int
            let gasLimit: String
            let gasPrice: String
        }
        let estimate: Estimate
        let transactionRequest: TransactionRequest
    }
    struct SolanaQuoteResponse: Codable {
        struct TransactionRequest: Codable {
            let data: String
        }
        let estimate: Estimate
        let transactionRequest: TransactionRequest
    }
    struct Estimate: Codable {
        let toAmount: String
        let toAmountMin: String
        let executionDuration: Decimal
    }

    case evm(EvmQuoteResponse)
    case solana(SolanaQuoteResponse)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let evmResponse = try? container.decode(EvmQuoteResponse.self) {
            self = .evm(evmResponse)
            return
        }

        if let solanaResponse = try? container.decode(SolanaQuoteResponse.self) {
            self = .solana(solanaResponse)
            return
        }

        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown QuoteResponse type")
    }
}
